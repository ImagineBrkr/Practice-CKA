#!/bin/bash
# This script was create to be used as a template file for Terraform
# If you want to directly run this file, replace every "$$" with "$" first and set the first variables
set -e

# --- CONFIGURATION ---
KUBE_VER=${KUBE_VER}
MASTER_NODE_PRIVATE_IP=${MASTER_NODE_PRIVATE_IP}
MASTER_NODE_PUBLIC_IP=${MASTER_NODE_PUBLIC_IP}
CLUSTER_ADMIN=${CLUSTER_ADMIN}
CLUSTER_NAME=${CLUSTER_NAME}
NODE_IP=${NODE_IP}
NODE_NAME=${NODE_NAME}
CNI_VERSION=${CNI_VERSION}

GENERATE_CERTS_USER=${GENERATE_CERTS_USER}

ARCH=$(uname -m)
  case $ARCH in
    armv7*) ARCH="arm";;
    aarch64) ARCH="arm64";;
    x86_64) ARCH="amd64";;
  esac

CNI_BIN_DIR="/opt/cni/bin"
KUBE_BIN_DIR="/opt/kubernetes/bin"
KUBELET_BIN="$KUBE_BIN_DIR/kubelet"
KUBE_PROXY_BIN="$KUBE_BIN_DIR/kube-proxy"
KUBE_KUBECONFIG_DIR="/etc/kubernetes"

CA_DIR="/etc/kubernetes/pki/ca"
CA_CERT="$CA_DIR/ca.crt"

KUBE_CERTIFICATES_DIR="/etc/kubernetes/pki"


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
mkdir -p $KUBE_BIN_DIR
mkdir -p $CNI_BIN_DIR
mkdir -p $CA_DIR
mkdir -p $KUBE_CERTIFICATES_DIR
mkdir -p $KUBE_KUBECONFIG_DIR


#############################################
## --- WORKER NODE REGISTRATION SCRIPT --- ##
#############################################

# User creation. This user will be used by the master node
useradd -m -s /bin/bash $GENERATE_CERTS_USER
mkdir -p /home/$GENERATE_CERTS_USER/.ssh
touch /home/$GENERATE_CERTS_USER/.ssh/authorized_keys
chown $GENERATE_CERTS_USER:$GENERATE_CERTS_USER /home/$GENERATE_CERTS_USER

# Private key to execute script on master node
GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION="/home/$GENERATE_CERTS_USER/.ssh/master-node.pem"
cat <<EOF > $GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION
${generate_certs_user_master_private_key}
EOF
chmod 400 $GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION

# Add the public to authorized keys
echo "${generate_certs_user_worker_public_key}" | tee /home/$GENERATE_CERTS_USER/.ssh/authorized_keys

# Permissions
chmod 700 /home/$GENERATE_CERTS_USER/.ssh
chmod 600 /home/$GENERATE_CERTS_USER/.ssh/authorized_keys
chown -R $GENERATE_CERTS_USER:$GENERATE_CERTS_USER /home/$GENERATE_CERTS_USER/.ssh

# Execute generate_worker_certs script on master node
# Master node may have not yet created the authorized_keys entry
# so we add a small retry logic
max_retries=5
retry_interval=15
count=0

until /usr/bin/ssh -i "$GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$GENERATE_CERTS_USER@$MASTER_NODE_PRIVATE_IP" \
    "$NODE_NAME $NODE_IP"; do

  count=$((count + 1))
  echo "Intento $count fallido, reintentando en $retry_interval s..."

  if [[ $count -ge $max_retries ]]; then
    echo "Error: no se pudo conectar tras $max_retries intentos"
    exit 1
  fi

  sleep $retry_interval
done

tar -xvf /home/$GENERATE_CERTS_USER/worker-certs.tar.gz -C $KUBE_KUBECONFIG_DIR \
    --strip-components=1 --no-same-owner --owner=root --group=root
rm /home/$GENERATE_CERTS_USER/worker-certs.tar.gz

ls $KUBE_KUBECONFIG_DIR
KUBELET_KUBECONFIG=$KUBE_KUBECONFIG_DIR/kubelet.kubeconfig
PROXY_KUBECONFIG=$KUBE_KUBECONFIG_DIR/kube-proxy.kubeconfig
mv $KUBE_KUBECONFIG_DIR/ca.crt $CA_CERT


##################################
## --- kubelet INSTALLATION --- ##
##################################


curl -L https://dl.k8s.io/release/${KUBE_VER}/bin/linux/$ARCH/kubelet -o $KUBELET_BIN
chmod +x $KUBELET_BIN
$KUBELET_BIN --version

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
  --node-ip=${NODE_IP} \\

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


##############################
## --- CNI INSTALLATION --- ##
##############################

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
