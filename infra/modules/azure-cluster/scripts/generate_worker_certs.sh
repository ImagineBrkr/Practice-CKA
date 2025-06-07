#!/bin/bash
# Script in master node to be called by worker node to generate the necessary certificates
# If you want to manually create this script, change every "\$" to "$" and "\EOF" to "EOF".
# Also, set the first parameters to the required values
set -e

# Required parameters
# These parameters will be replaced on file creation
KUBECTL_BIN=$KUBECTL_BIN
CA_CERT=$CA_CERT
CA_KEY=$CA_KEY
KUBE_CERTIFICATES_DIR=$KUBE_CERTIFICATES_DIR
MASTER_NODE_PRIVATE_IP=$MASTER_NODE_PRIVATE_IP
CLUSTER_NAME=$CLUSTER_NAME
GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION=$GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION
GENERATE_CERTS_USER=$GENERATE_CERTS_USER

NODE_NAME=\$1
NODE_IP=\$2

# Helper functions
generate_certificate() {
    local COMPONENT=\$1      # Component name (e.g. "etcd", "apiserver")
    local CNF_FILE=\$2      # Path to OpenSSL config file
    local CERT_DIR=\$3      # Directory to store certificates
    local DAYS=\${4:-1000}  # Validity period in days (default: 1000)

    # Generate private key
    openssl genrsa -out "\$CERT_DIR/\$COMPONENT.key" 2048

    # Generate CSR
    openssl req -new \\
        -key "\$CERT_DIR/\$COMPONENT.key" \\
        -out "\$CERT_DIR/\$COMPONENT.csr" \\
        -config "\$CNF_FILE"

    # Sign certificate
    openssl x509 -req \\
        -in "\$CERT_DIR/\$COMPONENT.csr" \\
        -CA "\$CA_CERT" \\
        -CAkey "\$CA_KEY" \\
        -CAcreateserial \\
        -out "\$CERT_DIR/\$COMPONENT.crt" \\
        -days "\$DAYS" \\
        -extensions v3_req \\
        -extfile "\$CNF_FILE"
}

generate_client_cnf_file() {
    local CN=\$1            # e.g. "system:kube-scheduler"
    local O=\$2            # Optional organization field
    local FILE_LOCATION=\$3 # e.g. /etc/kubernetes/pki.kube-scheduler.cnf
    cat <<EOT > \$FILE_LOCATION
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = \$CN
\${O:+O = \${O}}

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOT
}

generate_cert_and_kubeconfig() {
    local COMPONENT=\$1      # e.g. "kube-scheduler", "kube-controller-manager"
    local CN=\$2            # e.g. "system:kube-scheduler"
    local O=\$3             # Optional organization field
    local KUBECONFIG_PATH=\$4 # Path to Kubeconfig file that will be created (e.g. ~/.kube/config)
    local SERVER_URL=\$5    # e.g. "https://127.0.0.1:6443"

    local CNF_FILE="\$KUBE_CERTIFICATES_DIR/\$COMPONENT.cnf"
    local KEY_FILE="\$KUBE_CERTIFICATES_DIR/\$COMPONENT.key"
    local CSR_FILE="\$KUBE_CERTIFICATES_DIR/\$COMPONENT.csr"
    local CERT_FILE="\$KUBE_CERTIFICATES_DIR/\$COMPONENT.crt"
    # Generate certificate configuration
    generate_client_cnf_file \\
      "\$CN" \\
      "\$O" \\
      "\$CNF_FILE"

    generate_certificate \\
      "\$COMPONENT" \\
      "\$CNF_FILE" \\
      "\$KUBE_CERTIFICATES_DIR" 

    # Generate kubeconfig
    \$KUBECTL_BIN config set-cluster \$CLUSTER_NAME \\
        --certificate-authority=\$CA_CERT \\
        --embed-certs=true \\
        --server=\$SERVER_URL \\
        --kubeconfig=\$KUBECONFIG_PATH

    \$KUBECTL_BIN config set-credentials \$CN \\
        --client-certificate=\$KUBE_CERTIFICATES_DIR/\$COMPONENT.crt \\
        --client-key=\$KUBE_CERTIFICATES_DIR/\$COMPONENT.key \\
        --embed-certs=true \\
        --kubeconfig=\$KUBECONFIG_PATH

    \$KUBECTL_BIN config set-context default \\
        --cluster=\${CLUSTER_NAME} \\
        --user=\$CN \\
        --kubeconfig=\$KUBECONFIG_PATH

    \$KUBECTL_BIN config use-context default \\
        --kubeconfig=\$KUBECONFIG_PATH
}

wait_for_kubectl() {
    local max_attempts=30
    local delay=10
    local attempt=1

    echo "Checking for kubectl availability..."
    while [ \$attempt -le \$max_attempts ]; do
        if [ -f "\$KUBECTL_BIN" ] && "\$KUBECTL_BIN" version --client &>/dev/null; then
            echo "kubectl is available"
            return 0
        fi
        echo "Attempt \$attempt/\$max_attempts: kubectl not available yet, waiting \$delay seconds..."
        sleep \$delay
        attempt=\$((attempt + 1))
    done

    echo "Error: kubectl not available after \$((max_attempts * delay)) seconds"
    exit 1
}

# Validate parameters
if [ -z "\$NODE_NAME" ] || [ -z "\$NODE_IP" ]; then
    echo "Usage: \$0 <node-name> <node-ip>"
    exit 1
fi

wait_for_kubectl

# Directories
WORK_DIR="/tmp/k8s-worker-\${NODE_NAME}"
mkdir -p "\${WORK_DIR}"

# Generate certificates and configs
generate_cert_and_kubeconfig \\
    "\${NODE_NAME}-kubelet" \\
    "system:node:\${NODE_NAME}" \\
    "system:nodes" \\
    "\${WORK_DIR}/kubelet.kubeconfig" \\
    "https://\${MASTER_NODE_PRIVATE_IP}:6443"

generate_cert_and_kubeconfig \\
    "kube-proxy" \\
    "system:kube-proxy" \\
    "" \\
    "\${WORK_DIR}/kube-proxy.kubeconfig" \\
    "https://\${MASTER_NODE_PRIVATE_IP}:6443"

# Copy CA certificate
cp "\${CA_CERT}" "\${WORK_DIR}/ca.crt"

# Create tarball
tar czf "\${WORK_DIR}.tar.gz" -C "\${WORK_DIR}" .

# Copy to worker node
scp -i \$GENERATE_CERTS_USER_WORKER_PRIVATE_KEY_LOCATION \\
    -o StrictHostKeyChecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    "\${WORK_DIR}.tar.gz" \\
    "\${GENERATE_CERTS_USER}@\${NODE_IP}:/home/\${GENERATE_CERTS_USER}/"

# Cleanup
rm -rf "\${WORK_DIR}" "\${WORK_DIR}.tar.gz"

echo "Certificates and configs sent to \${NODE_IP}"
