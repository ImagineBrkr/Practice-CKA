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

CA_DIR="/etc/kubernetes/pki/ca"
CA_KEY="$CA_DIR/ca.key"
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
