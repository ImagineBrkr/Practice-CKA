#!/bin/bash
# This script was create to be used as a template file for Terraform
# If you want to directly run this file, replace every "$$" with "$" first and set the first variables
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

GENERATE_CERTS_USER=${GENERATE_CERTS_USER}
REQUEST_KUBECONFIG_USER=${REQUEST_KUBECONFIG_USER}

ARCH=$(uname -m)
  case $ARCH in
    armv7*) ARCH="arm";;
    aarch64) ARCH="arm64";;
    x86_64) ARCH="amd64";;
  esac

ETCD_BIN_DIR="/opt/etcd/bin"
CNI_BIN_DIR="/opt/cni/bin"
KUBE_BIN_DIR="/opt/kubernetes/bin"
KUBECTL_BIN="$KUBE_BIN_DIR/kubectl"
KUBE_APISERVER_BIN="$KUBE_BIN_DIR/kube-apiserver"
KUBE_CONTROLLER_MANAGER_BIN="$KUBE_BIN_DIR/kube-controller-manager"
KUBE_SCHEDULER_BIN="$KUBE_BIN_DIR/kube-scheduler"
KUBELET_BIN="$KUBE_BIN_DIR/kubelet"
KUBE_PROXY_BIN="$KUBE_BIN_DIR/kube-proxy"

CA_DIR="/etc/kubernetes/pki/ca"
CA_KEY="$CA_DIR/ca.key"
CA_CERT="$CA_DIR/ca.crt"

KUBE_CERTIFICATES_DIR="/etc/kubernetes/pki"
ETCD_CERTIFICATES_DIR="/etc/etcd/pki"

KUBE_SCRIPTS_DIR="/opt/kubernetes/scripts"

# --- HELPER FUNCTIONS ---

generate_certificate() {
    local COMPONENT=$1      # Component name (e.g. "etcd", "apiserver")
    local CNF_FILE=$2      # Path to OpenSSL config file
    local CERT_DIR=$3      # Directory to store certificates
    local DAYS=$${4:-1000}  # Validity period in days (default: 1000)

    # Generate private key
    openssl genrsa -out "$CERT_DIR/$COMPONENT.key" 2048

    # Generate CSR
    openssl req -new \
        -key "$CERT_DIR/$COMPONENT.key" \
        -out "$CERT_DIR/$COMPONENT.csr" \
        -config "$CNF_FILE"

    # Sign certificate
    openssl x509 -req \
        -in "$CERT_DIR/$COMPONENT.csr" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$CERT_DIR/$COMPONENT.crt" \
        -days "$DAYS" \
        -extensions v3_req \
        -extfile "$CNF_FILE"
}

generate_client_cnf_file() {
    local CN=$1            # e.g. "system:kube-scheduler"
    local O=$2            # Optional organization field
    local FILE_LOCATION=$3 # e.g. /etc/kubernetes/pki.kube-scheduler.cnf
    cat <<EOF > $FILE_LOCATION
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
}

generate_cert_and_kubeconfig() {
    local COMPONENT=$1      # e.g. "kube-scheduler", "kube-controller-manager"
    local CN=$2            # e.g. "system:kube-scheduler"
    local O=$3             # Optional organization field
    local KUBECONFIG_PATH=$4 # Path to Kubeconfig file that will be created (e.g. ~/.kube/config)
    local SERVER_URL=$5    # e.g. "https://127.0.0.1:6443"

    local CNF_FILE="$KUBE_CERTIFICATES_DIR/$COMPONENT.cnf"
    local KEY_FILE="$KUBE_CERTIFICATES_DIR/$COMPONENT.key"
    local CSR_FILE="$KUBE_CERTIFICATES_DIR/$COMPONENT.csr"
    local CERT_FILE="$KUBE_CERTIFICATES_DIR/$COMPONENT.crt"
    # Generate certificate configuration
    generate_client_cnf_file \
      "$CN" \
      "$O" \
      "$CNF_FILE"

    generate_certificate \
      "$COMPONENT" \
      "$CNF_FILE" \
      "$KUBE_CERTIFICATES_DIR" 

    # Generate kubeconfig
    $KUBECTL_BIN config set-cluster $CLUSTER_NAME \
        --certificate-authority=$CA_CERT \
        --embed-certs=true \
        --server=$SERVER_URL \
        --kubeconfig=$KUBECONFIG_PATH

    $KUBECTL_BIN config set-credentials $CN \
        --client-certificate=$KUBE_CERTIFICATES_DIR/$COMPONENT.crt \
        --client-key=$KUBE_CERTIFICATES_DIR/$COMPONENT.key \
        --embed-certs=true \
        --kubeconfig=$KUBECONFIG_PATH

    $KUBECTL_BIN config set-context default \
        --cluster=${CLUSTER_NAME} \
        --user=$CN \
        --kubeconfig=$KUBECONFIG_PATH

    $KUBECTL_BIN config use-context default \
        --kubeconfig=$KUBECONFIG_PATH
}


###########################
## --- INITIAL SETUP --- ##
###########################


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

# --- Create folders ---
mkdir -p $ETCD_BIN_DIR
mkdir -p $KUBE_BIN_DIR
mkdir -p $CNI_BIN_DIR
mkdir -p $CA_DIR
mkdir -p $ETCD_CERTIFICATES_DIR
mkdir -p $KUBE_CERTIFICATES_DIR
mkdir -p $KUBE_SCRIPTS_DIR

# --- Create Certificate Authority for ETCD and Kubernetes ---

openssl genrsa -out $CA_KEY 2048
openssl req -x509 -new -nodes -key $CA_KEY -subj "/CN=kubernetes-ca" -days 1000 -out $CA_CERT
chmod 644 $CA_CERT
cp $CA_CERT /usr/local/share/ca-certificates/ca.crt
update-ca-certificates


#############################################
## --- WORKER NODE REGISTRATION SCRIPT --- ##
#############################################


GENERATE_CERTS_SCRIPT_LOCATION="$KUBE_SCRIPTS_DIR/generate_worker_certs.sh"

# User creation. This user will be used by the worker node
useradd -m -s /bin/bash $GENERATE_CERTS_USER
mkdir -p /home/$GENERATE_CERTS_USER/.ssh
touch /home/$GENERATE_CERTS_USER/.ssh/authorized_keys

# Private key to use scp with worker nodes
GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION="/home/$GENERATE_CERTS_USER/.ssh/worker-nodes.pem"
cat <<EOF > $GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION
${generate_certs_user_worker_private_key}
EOF
chmod 400 $GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION

# Script to generate certs and send them to worker nodes
cat <<EOF > $GENERATE_CERTS_SCRIPT_LOCATION
${generate_certs_script}
EOF
chmod 700 $GENERATE_CERTS_SCRIPT_LOCATION


# The SSH Key can only be used to execute this script
echo "command=\"sudo $GENERATE_CERTS_SCRIPT_LOCATION \$SSH_ORIGINAL_COMMAND\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${generate_certs_user_master_public_key}" | tee -a /home/$GENERATE_CERTS_USER/.ssh/authorized_keys

# Permissions
chmod 700 /home/$GENERATE_CERTS_USER/.ssh
chmod 600 /home/$GENERATE_CERTS_USER/.ssh/authorized_keys
chown -R $GENERATE_CERTS_USER:$GENERATE_CERTS_USER /home/$GENERATE_CERTS_USER/.ssh

echo "$GENERATE_CERTS_USER ALL=(ALL) NOPASSWD: $GENERATE_CERTS_SCRIPT_LOCATION *" | tee /etc/sudoers.d/$GENERATE_CERTS_USER
chmod 440 /etc/sudoers.d/$GENERATE_CERTS_USER


###############################
## --- ETCD INSTALLATION --- ##
###############################


curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-$ARCH.tar.gz \
     -o /tmp/etcd-${ETCD_VER}-linux-$ARCH.tar.gz
tar -xvf /tmp/etcd-${ETCD_VER}-linux-$ARCH.tar.gz -C $ETCD_BIN_DIR --strip-components=1 --no-same-owner

$ETCD_BIN_DIR/etcd --version

# ETCD cert and key

cat <<EOF > $ETCD_CERTIFICATES_DIR/etcd.cnf
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

generate_certificate \
      "etcd" \
      "$ETCD_CERTIFICATES_DIR/etcd.cnf" \
      "$ETCD_CERTIFICATES_DIR"

# Client certificates for kube-apiserver
generate_client_cnf_file \
      "kube-apiserver" \
      "" \
      "$KUBE_CERTIFICATES_DIR/apiserver-etcd-client.cnf"

generate_certificate \
      "apiserver-etcd-client" \
      "$KUBE_CERTIFICATES_DIR/apiserver-etcd-client.cnf" \
      "$KUBE_CERTIFICATES_DIR" 


# ETCD Configuration
mkdir -p /var/lib/etcd
cat <<EOF > /etc/etcd/etcd.conf.yml
name: master
data-dir: /var/lib/etcd
listen-client-urls: https://127.0.0.1:2379
advertise-client-urls: https://127.0.0.1:2379
client-transport-security:
  cert-file: $ETCD_CERTIFICATES_DIR/etcd.crt
  key-file: $ETCD_CERTIFICATES_DIR/etcd.key
  client-cert-auth: true
  trusted-ca-file: $CA_CERT
EOF

# Systemd configuration
cat <<EOF > /etc/systemd/system/etcd.service
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
ExecStart=$ETCD_BIN_DIR/etcd --config-file /etc/etcd/etcd.conf.yml
Restart=always
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now etcd


#########################################
## --- Kube-apiserver INSTALLATION --- ##
#########################################


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-apiserver -o $KUBE_APISERVER_BIN
chmod +x $KUBE_APISERVER_BIN
$KUBE_APISERVER_BIN --version

# Kube-apiserver tls certificates

# Cert for kube-apiserver (CN = kube-apiserver)
cat <<EOF > $KUBE_CERTIFICATES_DIR/kube-apiserver.cnf
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

generate_certificate \
      "kube-apiserver" \
      "$KUBE_CERTIFICATES_DIR/kube-apiserver.cnf" \
      "$KUBE_CERTIFICATES_DIR"

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
ExecStart=$KUBE_APISERVER_BIN \\
  --advertise-address=${MASTER_NODE_PUBLIC_IP} \\
  --bind-address=0.0.0.0 \\
  --secure-port=6443 \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --etcd-cafile=$CA_CERT \\
  --etcd-certfile=$KUBE_CERTIFICATES_DIR/apiserver-etcd-client.crt \\
  --etcd-keyfile=$KUBE_CERTIFICATES_DIR/apiserver-etcd-client.key \\
  --client-ca-file=$CA_CERT \\
  --tls-cert-file=$KUBE_CERTIFICATES_DIR/kube-apiserver.crt \\
  --tls-private-key-file=$KUBE_CERTIFICATES_DIR/kube-apiserver.key \\
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
    "https://127.0.0.1:6443"

chown ${CLUSTER_ADMIN}:${CLUSTER_ADMIN} $KUBECONFIG


##################################################
## --- kube-controller-manager INSTALLATION --- ##
##################################################


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-controller-manager -o $KUBE_CONTROLLER_MANAGER_BIN
chmod +x $KUBE_CONTROLLER_MANAGER_BIN
$KUBE_CONTROLLER_MANAGER_BIN --version

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
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/
After=network.target

[Service]
ExecStart=$KUBE_CONTROLLER_MANAGER_BIN \\
  --kubeconfig=$KCM_KUBECONFIG \\
  --root-ca-file=$CA_CERT \\
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key \\
  --cluster-signing-cert-file=$CA_CERT \\
  --cluster-signing-key-file=$CA_KEY \\
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


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-scheduler -o $KUBE_SCHEDULER_BIN
chmod +x $KUBE_SCHEDULER_BIN
$KUBE_SCHEDULER_BIN --version

# Kubeconfig file for kube-scheduler
KUBE_SCHEDULER_KUBECONFIG="/etc/kubernetes/kube-scheduler.kubeconfig"

# Certificate and kubeconfig generatior to communicate with kube-apiserver
generate_cert_and_kubeconfig \
    "kube-scheduler" \
    "system:kube-scheduler" \
    "" \
    "$KUBE_SCHEDULER_KUBECONFIG" \
    "https://127.0.0.1:6443"

# Service configuration
cat <<EOF > /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://kubernetes.io/docs/
After=network.target

[Service]
ExecStart=$KUBE_SCHEDULER_BIN \
  --kubeconfig=$KUBE_SCHEDULER_KUBECONFIG \
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


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kubelet -o $KUBELET_BIN
chmod +x $KUBELET_BIN
$KUBELET_BIN --version

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
    clientCAFile: $CA_CERT
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
ExecStart=$KUBELET_BIN \\
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


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kube-proxy -o $KUBE_PROXY_BIN
chmod +x $KUBE_PROXY_BIN
$KUBE_PROXY_BIN --version

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
Documentation=https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/
After=network.target

[Service]
ExecStart=$KUBE_PROXY_BIN \
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

# CNI binaries installation
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-$ARCH-${CNI_VERSION}.tgz" -o /tmp/cni-plugins-linux-$ARCH-${CNI_VERSION}.tgz
tar -xvf /tmp/cni-plugins-linux-$ARCH-${CNI_VERSION}.tgz -C $CNI_BIN_DIR --strip-components=1 --no-same-owner

systemctl restart kubelet

# kube-flannel Kubernetes resources obtained from resources/kube-flannel.yaml
curl -L https://raw.githubusercontent.com/flannel-io/flannel/refs/heads/master/Documentation/kube-flannel.yml -o /opt/kubernetes/kube-flannel.yml
$KUBECTL_BIN apply -f /opt/kubernetes/kube-flannel.yml --kubeconfig=$KUBECONFIG


#######################################
## --- REQUEST KUBECONFIG SCRIPT --- ##
#######################################


PUBLIC_KUBECONFIG=/home/${REQUEST_KUBECONFIG_USER}/.kube/public-config

# Certificate generation
generate_cert_and_kubeconfig \
    "kubeadmin" \
    "${CLUSTER_ADMIN}" \
    "system:masters" \
    "$PUBLIC_KUBECONFIG" \
    "https://${MASTER_NODE_PUBLIC_IP}:6443"

# User creation. This user will be used by the worker node
useradd -m -s /bin/bash $REQUEST_KUBECONFIG_USER
mkdir -p /home/$REQUEST_KUBECONFIG_USER/.ssh
touch /home/$REQUEST_KUBECONFIG_USER/.ssh/authorized_keys

# The SSH Key can only be used to execute this script
echo "command=\"cat $PUBLIC_KUBECONFIG\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${request_kubeconfig_user_public_key}" | tee -a /home/$REQUEST_KUBECONFIG_USER/.ssh/authorized_keys

# Permissions
chmod 700 /home/$REQUEST_KUBECONFIG_USER/.ssh
chmod 600 /home/$REQUEST_KUBECONFIG_USER/.ssh/authorized_keys
chown -R $REQUEST_KUBECONFIG_USER:$REQUEST_KUBECONFIG_USER /home/$REQUEST_KUBECONFIG_USER/.ssh

chown ${REQUEST_KUBECONFIG_USER}:${REQUEST_KUBECONFIG_USER} $PUBLIC_KUBECONFIG

