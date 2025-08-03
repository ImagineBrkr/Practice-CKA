resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_pem
  filename        = abspath(var.private_key_path)
  file_permission = "0600"
}

# SSH keys for generate_certs script
resource "tls_private_key" "generate_certs_user_ssh_key_master" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "generate_certs_user_ssh_key_worker" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# SSH key for requesting cluster kubeconfig
resource "tls_private_key" "kubeconfig_user_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "request_kubeconfig_user_private_key" {
  content         = tls_private_key.kubeconfig_user_ssh_key.private_key_pem
  filename        = abspath(var.request_kubeconfig_user_private_key_path)
  file_permission = "0600"
}
