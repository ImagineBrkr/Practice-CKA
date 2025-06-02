#!/bin/bash
set -e

# --- CONFIGURATION ---
KUBE_VER=${KUBE_VER}
ETCD_VER=${ETCD_VER}
MASTER_NODE_PRIVATE_IP=${MASTER_NODE_PRIVATE_IP}
MASTER_NODE_PUBLIC_IP=${MASTER_NODE_PUBLIC_IP}
CLUSTER_ADMIN=${CLUSTER_ADMIN}
CLUSTER_NAME=${CLUSTER_NAME}

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

curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
     -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar -xvf etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download --strip-components=1 --no-same-owner
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

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

curl -LO https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kube-apiserver
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


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl -o /opt/kubernetes/bin/kubectl
chmod +x /opt/kubernetes/bin/kubectl

# Generate client certificate signed by the cluster's CA.
cat <<EOF > /etc/kubernetes/pki/kubeadmin.cnf
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = ${CLUSTER_ADMIN}
O = system:masters

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

openssl genrsa -out /etc/kubernetes/pki/kubeadmin.key 2048

openssl req -new -key /etc/kubernetes/pki/kubeadmin.key -out /etc/kubernetes/pki/kubeadmin.csr \
  -config /etc/kubernetes/pki/kubeadmin.cnf

openssl x509 -req -in /etc/kubernetes/pki/kubeadmin.csr -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial \
  -out /etc/kubernetes/pki/kubeadmin.crt -days 1000 \
  -extensions v3_req -extfile /etc/kubernetes/pki/kubeadmin.cnf

KUBECONFIG=/home/${CLUSTER_ADMIN}/.kube/config
mkdir -p "$(dirname "$KUBECONFIG")"
chown ${CLUSTER_ADMIN}:${CLUSTER_ADMIN} /home/${CLUSTER_ADMIN}/.kube

/opt/kubernetes/bin/kubectl config set-cluster ${CLUSTER_NAME} \
  --server=https://${MASTER_NODE_PUBLIC_IP}:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig=$KUBECONFIG

/opt/kubernetes/bin/kubectl config set-credentials ${CLUSTER_ADMIN} \
  --client-certificate=/etc/kubernetes/pki/kubeadmin.crt \
  --client-key=/etc/kubernetes/pki/kubeadmin.key \
  --embed-certs=true \
  --kubeconfig=$KUBECONFIG

/opt/kubernetes/bin/kubectl config set-context ${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${CLUSTER_ADMIN} \
  --kubeconfig=$KUBECONFIG

/opt/kubernetes/bin/kubectl config use-context ${CLUSTER_NAME} \
  --kubeconfig=$KUBECONFIG

chown ${CLUSTER_ADMIN}:${CLUSTER_ADMIN} $KUBECONFIG


##################################################
## --- kube-controller-manager INSTALLATION --- ##
##################################################


mkdir -p /opt/kubernetes/bin
cd /opt/kubernetes/bin

curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kube-controller-manager -o /opt/kubernetes/bin/kube-controller-manager
chmod +x /opt/kubernetes/bin/kube-controller-manager

# Client certificates to comunicate with kube-apiserver using TLS
cat <<EOF > /etc/kubernetes/pki/controller-manager.cnf
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = system:kube-controller-manager

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

openssl genrsa -out /etc/kubernetes/pki/kube-controller-manager.key 2048

openssl req -new -key /etc/kubernetes/pki/kube-controller-manager.key \
  -out /etc/kubernetes/pki/kube-controller-manager.csr \
  -config /etc/kubernetes/pki/controller-manager.cnf

openssl x509 -req -in /etc/kubernetes/pki/kube-controller-manager.csr \
  -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial \
  -out /etc/kubernetes/pki/kube-controller-manager.crt -days 1000 \
  -extensions v3_req -extfile /etc/kubernetes/pki/controller-manager.cnf

# Kubeconfig file for kube-controller-manager
KCM_KUBECONFIG="/etc/kubernetes/kube-controller-manager.kubeconfig"

/opt/kubernetes/bin/kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=$KCM_KUBECONFIG

/opt/kubernetes/bin/kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=/etc/kubernetes/pki/kube-controller-manager.crt \
  --client-key=/etc/kubernetes/pki/kube-controller-manager.key \
  --embed-certs=true \
  --kubeconfig=$KCM_KUBECONFIG

/opt/kubernetes/bin/kubectl config set-context default \
  --cluster=${CLUSTER_NAME} \
  --user=system:kube-controller-manager \
  --kubeconfig=$KCM_KUBECONFIG

/opt/kubernetes/bin/kubectl config use-context default \
  --kubeconfig=$KCM_KUBECONFIG


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

curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kube-scheduler -o /opt/kubernetes/bin/kube-scheduler
chmod +x /opt/kubernetes/bin/kube-scheduler

# Client certificate to use with kube-apiserver
cat <<EOF > /etc/kubernetes/pki/scheduler.cnf
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = system:kube-scheduler

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

openssl genrsa -out /etc/kubernetes/pki/kube-scheduler.key 2048

openssl req -new -key /etc/kubernetes/pki/kube-scheduler.key \
  -out /etc/kubernetes/pki/kube-scheduler.csr \
  -config /etc/kubernetes/pki/scheduler.cnf

openssl x509 -req -in /etc/kubernetes/pki/kube-scheduler.csr \
  -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial \
  -out /etc/kubernetes/pki/kube-scheduler.crt -days 1000 \
  -extensions v3_req -extfile /etc/kubernetes/pki/scheduler.cnf

SCHED_KUBECONFIG="/etc/kubernetes/kube-scheduler.kubeconfig"

/opt/kubernetes/bin/kubectl config set-cluster manual-k8s \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=$SCHED_KUBECONFIG

/opt/kubernetes/bin/kubectl config set-credentials system:kube-scheduler \
  --client-certificate=/etc/kubernetes/pki/kube-scheduler.crt \
  --client-key=/etc/kubernetes/pki/kube-scheduler.key \
  --embed-certs=true \
  --kubeconfig=$SCHED_KUBECONFIG

/opt/kubernetes/bin/kubectl config set-context default \
  --cluster=manual-k8s \
  --user=system:kube-scheduler \
  --kubeconfig=$SCHED_KUBECONFIG

/opt/kubernetes/bin/kubectl config use-context default --kubeconfig=$SCHED_KUBECONFIG

# Service configuration
cat <<EOF > /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://kubernetes.io/docs/
After=network.target

[Service]
ExecStart=/opt/kubernetes/bin/kube-scheduler \
  --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
  --leader-elect=true

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler
