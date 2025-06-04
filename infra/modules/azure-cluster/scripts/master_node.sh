#!/bin/bash
set -e

# --- CONFIGURATION ---
KUBE_VER=${KUBE_VER}
ETCD_VER=${ETCD_VER}
MASTER_NODE_PRIVATE_IP=${MASTER_NODE_PRIVATE_IP}
MASTER_NODE_PUBLIC_IP=${MASTER_NODE_PUBLIC_IP}
CLUSTER_ADMIN=${CLUSTER_ADMIN}
CLUSTER_NAME=${CLUSTER_NAME}
NODE_NAME=${NODE_NAME}
CNI_VERSION=${CNI_VERSION}
KUBECTL_BIN="/opt/kubernetes/bin/kubectl"

ARCH=$(uname -m)
  case $ARCH in
    armv7*) ARCH="arm";;
    aarch64) ARCH="arm64";;
    x86_64) ARCH="amd64";;
  esac

# --- HELPER FUNCTIONS ---

generate_cert_and_kubeconfig() {
    local COMPONENT=$1      # e.g. "kube-scheduler", "kube-controller-manager"
    local CN=$2            # e.g. "system:kube-scheduler"
    local O=$3             # Optional organization field
    local KUBECONFIG_PATH=$4
    local SERVER_URL=$5    # e.g. "https://127.0.0.1:6443"
    
    # Generate certificate configuration
    cat <<EOF > /etc/kubernetes/pki/$COMPONENT.cnf
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = $CN
$${O:+O = $${O}}

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

    # Generate private key
    openssl genrsa -out /etc/kubernetes/pki/$COMPONENT.key 2048

    # Generate CSR
    openssl req -new -key /etc/kubernetes/pki/$COMPONENT.key \
        -out /etc/kubernetes/pki/$COMPONENT.csr \
        -config /etc/kubernetes/pki/$COMPONENT.cnf

    # Sign certificate
    openssl x509 -req -in /etc/kubernetes/pki/$COMPONENT.csr \
        -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial \
        -out /etc/kubernetes/pki/$COMPONENT.crt -days 1000 \
        -extensions v3_req -extfile /etc/kubernetes/pki/$COMPONENT.cnf

    # Generate kubeconfig
    $KUBECTL_BIN config set-cluster $CLUSTER_NAME \
        --certificate-authority=/etc/kubernetes/pki/ca.crt \
        --embed-certs=true \
        --server=$SERVER_URL \
        --kubeconfig=$KUBECONFIG_PATH

    $KUBECTL_BIN config set-credentials $CN \
        --client-certificate=/etc/kubernetes/pki/$COMPONENT.crt \
        --client-key=/etc/kubernetes/pki/$COMPONENT.key \
        --embed-certs=true \
        --kubeconfig=$KUBECONFIG_PATH

    $KUBECTL_BIN config set-context default \
        --cluster=${CLUSTER_NAME} \
        --user=$CN \
        --kubeconfig=$KUBECONFIG_PATH

    $KUBECTL_BIN config use-context default \
        --kubeconfig=$KUBECONFIG_PATH
}

# --- Disable swap ---
# Kubernetes requires that you disable memory swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# --- Install dependencies ---
apt update
apt install -y apt-transport-https curl containerd

# --- Configure containerd ---
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

###############################
## --- ETCD INSTALLATION --- ##
###############################

mkdir -p /opt/etcd
mkdir /tmp/etcd-download
cd /tmp

curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-$ARCH.tar.gz \
     -o /tmp/etcd-${ETCD_VER}-linux-$ARCH.tar.gz
tar -xvf etcd-${ETCD_VER}-linux-$ARCH.tar.gz -C /tmp/etcd-download --strip-components=1 --no-same-owner
rm -f /tmp/etcd-${ETCD_VER}-linux-$ARCH.tar.gz

/tmp/etcd-download/etcd --version
/tmp/etcd-download/etcdctl version
/tmp/etcd-download/etcdutl version

mv /tmp/etcd-download/etcd* /opt/etcd/

# --- Generate etcd TLS Certificates ---
mkdir -p /etc/etcd/pki

# CA
openssl genrsa -out /etc/etcd/pki/ca.key 2048
openssl req -x509 -new -nodes -key /etc/etcd/pki/ca.key -subj "/CN=etcd-ca" -days 1000 -out /etc/etcd/pki/ca.crt

# Add CA to system's trustedd certificates directory 
cp /etc/etcd/pki/ca.crt  /usr/local/share/ca-certificates/etcd-ca.crt
update-ca-certificates

# ETCD cert and key
openssl genrsa -out /etc/etcd/pki/etcd.key 2048

cat <<EOF > /etc/etcd/pki/etcd-openssl.cnf
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = etcd

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = ${MASTER_NODE_PRIVATE_IP}
EOF

# CSR
openssl req -new -key /etc/etcd/pki/etcd.key -out /etc/etcd/pki/etcd.csr -config /etc/etcd/pki/etcd-openssl.cnf

# Signed cert
openssl x509 -req -in /etc/etcd/pki/etcd.csr -CA /etc/etcd/pki/ca.crt -CAkey /etc/etcd/pki/ca.key -CAcreateserial \
  -out /etc/etcd/pki/etcd.crt -days 1000 -extensions v3_req -extfile /etc/etcd/pki/etcd-openssl.cnf

# Client certificates for kube-apiserver
cat <<EOF > /etc/etcd/pki/apiserver-etcd-client.cnf
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = kube-apiserver

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

# Key
openssl genrsa -out /etc/etcd/pki/apiserver-etcd-client.key 2048

# CSR
openssl req -new -key /etc/etcd/pki/apiserver-etcd-client.key \
  -out /etc/etcd/pki/apiserver-etcd-client.csr \
  -config /etc/etcd/pki/apiserver-etcd-client.cnf

# Cert
openssl x509 -req -in /etc/etcd/pki/apiserver-etcd-client.csr \
  -CA /etc/etcd/pki/ca.crt -CAkey /etc/etcd/pki/ca.key -CAcreateserial \
  -out /etc/etcd/pki/apiserver-etcd-client.crt -days 1000 \
  -extensions v3_req -extfile /etc/etcd/pki/apiserver-etcd-client.cnf

# ETCD Configuration
mkdir -p /var/lib/etcd
cat <<EOF > /etc/etcd/etcd.conf.yml
name: master
data-dir: /var/lib/etcd
listen-client-urls: https://127.0.0.1:2379
advertise-client-urls: https://127.0.0.1:2379
client-transport-security:
  cert-file: /etc/etcd/pki/etcd.crt
  key-file: /etc/etcd/pki/etcd.key
  client-cert-auth: true
  trusted-ca-file: /etc/etcd/pki/ca.crt
EOF

# Systemd configuration
cat <<EOF > /etc/systemd/system/etcd.service
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
ExecStart=/opt/etcd/etcd --config-file /etc/etcd/etcd.conf.yml
Restart=always
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now etcd

# Verification
sleep 10
curl --cacert /etc/etcd/pki/ca.crt --cert /etc/etcd/pki/apiserver-etcd-client.crt --key /etc/etcd/pki/apiserver-etcd-client.key \
  -L https://127.0.0.1:2379/readyz -v


#########################################
## --- Kube-apiserver INSTALLATION --- ##
#########################################


mkdir -p /opt/kubernetes/bin
cd /opt/kubernetes/bin

curl -LO https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-apiserver
chmod +x kube-apiserver

# Kube-apiserver tls certificates

mkdir -p /etc/kubernetes/pki
cp /etc/etcd/pki/ca.crt /etc/kubernetes/pki/ca.crt
cp /etc/etcd/pki/ca.key /etc/kubernetes/pki/ca.key
cp /etc/etcd/pki/apiserver* /etc/kubernetes/pki/

# Cert for kube-apiserver (CN = kube-apiserver)
cat <<EOF > /etc/kubernetes/pki/apiserver.cnf
[ req ]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_req

[ req_distinguished_name ]
CN = kube-apiserver

[ v3_req ]
subjectAltName = @alt_names
extendedKeyUsage = serverAuth

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = 127.0.0.1
IP.2 = ${MASTER_NODE_PRIVATE_IP}
IP.3 = ${MASTER_NODE_PUBLIC_IP}
IP.4 = 10.96.0.1
EOF

openssl genrsa -out /etc/kubernetes/pki/apiserver.key 2048

openssl req -new -key /etc/kubernetes/pki/apiserver.key -out /etc/kubernetes/pki/apiserver.csr \
  -config /etc/kubernetes/pki/apiserver.cnf

openssl x509 -req -in /etc/kubernetes/pki/apiserver.csr -CA /etc/etcd/pki/ca.crt \
  -CAkey /etc/etcd/pki/ca.key -CAcreateserial \
  -out /etc/kubernetes/pki/apiserver.crt -days 1000 \
  -extensions v3_req -extfile /etc/kubernetes/pki/apiserver.cnf

# Private Key for service accounts
openssl genrsa -out /etc/kubernetes/pki/sa.key 2048
openssl rsa -in /etc/kubernetes/pki/sa.key -pubout -out /etc/kubernetes/pki/sa.pub

# Service configuration
cat <<EOF > /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
After=network.target

[Service]
ExecStart=/opt/kubernetes/bin/kube-apiserver \\
  --advertise-address=${MASTER_NODE_PUBLIC_IP} \\
  --bind-address=0.0.0.0 \\
  --secure-port=6443 \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --etcd-cafile=/etc/etcd/pki/ca.crt \\
  --etcd-certfile=/etc/etcd/pki/apiserver-etcd-client.crt \\
  --etcd-keyfile=/etc/etcd/pki/apiserver-etcd-client.key \\
  --client-ca-file=/etc/kubernetes/pki/ca.crt \\
  --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \\
  --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --authorization-mode=Node,RBAC \\
  # Certificates used by kube-apiserver (client) to talk to kubelet (server)
  # --kubelet-client-certificate=/etc/kubernetes/pki/apiserver.crt \\
  # --kubelet-client-key=/etc/kubernetes/pki/apiserver.key \\
  --service-account-key-file=/etc/kubernetes/pki/sa.pub \\
  --service-account-signing-key-file=/etc/kubernetes/pki/sa.key \\
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
  --enable-bootstrap-token-auth=true

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver


##################################
## --- Kubectl INSTALLATION --- ##
##################################


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kubectl -o $KUBECTL_BIN
chmod +x $KUBECTL_BIN
ln -s $KUBECTL_BIN /bin/kubectl

# Generate client certificate signed by the cluster's CA.
KUBECONFIG=/home/${CLUSTER_ADMIN}/.kube/config
mkdir -p "$(dirname "$KUBECONFIG")"
chown ${CLUSTER_ADMIN}:${CLUSTER_ADMIN} /home/${CLUSTER_ADMIN}/.kube

generate_cert_and_kubeconfig \
    "kubeadmin" \
    "${CLUSTER_ADMIN}" \
    "system:masters" \
    "$KUBECONFIG" \
    "https://${MASTER_NODE_PUBLIC_IP}:6443"

chown ${CLUSTER_ADMIN}:${CLUSTER_ADMIN} $KUBECONFIG


##################################################
## --- kube-controller-manager INSTALLATION --- ##
##################################################


mkdir -p /opt/kubernetes/bin
cd /opt/kubernetes/bin

curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-controller-manager -o /opt/kubernetes/bin/kube-controller-manager
chmod +x /opt/kubernetes/bin/kube-controller-manager

# Kubeconfig file for kube-controller-manager
KCM_KUBECONFIG="/etc/kubernetes/kube-controller-manager.kubeconfig"

# Certificate and kubeconfig generatior to communicate with kube-apiserver
generate_cert_and_kubeconfig \
    "kube-controller-manager" \
    "system:kube-controller-manager" \
    "" \
    "$KCM_KUBECONFIG" \
    "https://127.0.0.1:6443"

# Service configuration
cat <<EOF > /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
After=network.target

[Service]
ExecStart=/opt/kubernetes/bin/kube-controller-manager \\
  --kubeconfig=$KCM_KUBECONFIG \\
  --root-ca-file=/etc/kubernetes/pki/ca.crt \\
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key \\
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/etc/kubernetes/pki/ca.key \\
  --use-service-account-credentials=true \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --allocate-node-cidrs=true \\
  --cluster-cidr=10.244.0.0/16 \\
  --leader-elect=true

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager


#########################################
## --- kube-scheduler INSTALLATION --- ##
#########################################


mkdir -p /opt/kubernetes/bin
cd /opt/kubernetes/bin

curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-scheduler -o /opt/kubernetes/bin/kube-scheduler
chmod +x /opt/kubernetes/bin/kube-scheduler

# Kubeconfig file for kube-scheduler
SCHED_KUBECONFIG="/etc/kubernetes/kube-scheduler.kubeconfig"

# Certificate and kubeconfig generatior to communicate with kube-apiserver
generate_cert_and_kubeconfig \
    "kube-scheduler" \
    "system:kube-scheduler" \
    "" \
    "$SCHED_KUBECONFIG" \
    "https://127.0.0.1:6443"

# Service configuration
cat <<EOF > /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://kubernetes.io/docs/
After=network.target

[Service]
ExecStart=/opt/kubernetes/bin/kube-scheduler \
  --kubeconfig=$SCHED_KUBECONFIG \
  --leader-elect=true

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler


##################################
## --- kubelet INSTALLATION --- ##
##################################


mkdir -p /opt/kubernetes/bin
cd /opt/kubernetes/bin

curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kubelet -o /opt/kubernetes/bin/kubelet
chmod +x /opt/kubernetes/bin/kubelet

# Kubeconfig file for master node's kubelet
KUBELET_KUBECONFIG="/etc/kubernetes/kubelet.kubeconfig"

# Certificate and kubeconfig generatior to communicate with kube-apiserver
generate_cert_and_kubeconfig \
    "${NODE_NAME}-kubelet" \
    "system:node:${NODE_NAME}" \
    "system:nodes" \
    "$KUBELET_KUBECONFIG" \
    "https://127.0.0.1:6443"

# Kubelet service configuration
cat <<EOF > /etc/kubernetes/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
enableServer: true
authentication:
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
  anonymous:
    enabled: true
  webhook:
    enabled: true
authorization:
  mode: AlwaysAllow
clusterDomain: cluster.local
clusterDNS:
  - 10.96.0.10
cgroupDriver: systemd
failSwapOn: true
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
EOF

cat <<EOF > /etc/systemd/system/kubelet.service
[Unit]
Description=Kubelet
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
After=network.target

[Service]
ExecStart=/opt/kubernetes/bin/kubelet \\
  --kubeconfig=$KUBELET_KUBECONFIG \\
  --config=/etc/kubernetes/kubelet-config.yaml \\
  --node-ip=${MASTER_NODE_PRIVATE_IP} \\

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet


#####################################
## --- kube-proxy INSTALLATION --- ##
#####################################


mkdir -p /opt/kubernetes/bin
cd /opt/kubernetes/bin

curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-proxy -o /opt/kubernetes/bin/kube-proxy
chmod +x /opt/kubernetes/bin/kube-proxy

# Kubeconfig file for master node's kubelet
PROXY_KUBECONFIG="/etc/kubernetes/kube-proxy.kubeconfig"

# Certificate and kubeconfig generatior to communicate with kube-apiserver
generate_cert_and_kubeconfig \
    "kube-proxy" \
    "system:kube-proxy" \
    "" \
    "$PROXY_KUBECONFIG" \
    "https://127.0.0.1:6443"

# Service config
cat <<EOF > /etc/kubernetes/kube-proxy-config.yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "iptables"
clusterCIDR: "10.244.0.0/16"
clientConnection:
  kubeconfig: "$PROXY_KUBECONFIG"
EOF

cat <<EOF > /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
ExecStart=/opt/kubernetes/bin/kube-proxy \
  --config=/etc/kubernetes/kube-proxy-config.yaml

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy


######################################
## --- FLANNEL CNI INSTALLATION --- ##
######################################

# Necessary OS configurations:
modprobe br_netfilter
echo "br_netfilter" > /etc/modules-load.d/k8s.conf

cat <<EOF > /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system


mkdir -p /opt/cni/bin
cd /opt/cni/bin

curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-$ARCH-${CNI_VERSION}.tgz" -o /tmp/cni-plugins.tgz
tar -xvf /tmp/cni-plugins.tgz -C /opt/cni/bin --strip-components=1 --no-same-owner
rm /tmp/cni-plugins.tgz

systemctl restart kubelet

# kube-flannel Kubernetes resources obtained from resources/kube-flannel.yaml
curl -L https://raw.githubusercontent.com/flannel-io/flannel/refs/heads/master/Documentation/kube-flannel.yml -o /opt/kubernetes/kube-flannel.yml
/opt/kubernetes/bin/kubectl apply -f /opt/kubernetes/kube-flannel.yml --kubeconfig=$KUBECONFIG
