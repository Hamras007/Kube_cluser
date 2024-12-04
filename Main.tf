# Terraform Configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}


provider "aws" {
  region = "ap-south-1"
}

# Generate SSH key
resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload SSH public key to AWS as Key Pair
resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-key"
  public_key = tls_private_key.k8s_key.public_key_openssh
}

# Security Group for Kubernetes
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-security-group"
  description = "Allow necessary traffic for Kubernetes cluster"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Kubernetes API Server traffic"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow pod communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-sg"
  }
}

# CREATING PRIVATE_KEY.PEM

resource "local_file" "private_key_file" {
  content  = tls_private_key.k8s_key.private_key_pem
  filename = "${path.module}/private_key.pem"
}

resource "null_resource" "set_permissions" {
  depends_on = [local_file.private_key_file]

  provisioner "local-exec" {
    command = "chmod 400 ${local_file.private_key_file.filename}"
  }
}


# Control Plane Node
resource "aws_instance" "control_plane" {
  ami           = "ami-09b0a86a2c84101e1" # Debian AMI ID
  instance_type = "t2.medium"
  key_name      = aws_key_pair.k8s_key.key_name
  security_groups = [aws_security_group.k8s_sg.name]

  tags = {
    Name = "k8s-control-plane"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
    delete_on_termination = true
}
}

# worker node

resource "aws_instance" "worker_node" {
  ami           = "ami-09b0a86a2c84101e1"
  instance_type = "t2.medium"
  key_name      = aws_key_pair.k8s_key.key_name
  security_groups = [aws_security_group.k8s_sg.name]

  tags = {
    Name = "k8s-worker-node"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
    delete_on_termination = true
}
}

# Outputs
output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip
}

output "worker_node_ip" {
  value = aws_instance.worker_node.public_ip
}

output "private_key" {
  value     = tls_private_key.k8s_key.private_key_pem
  sensitive = true
}

resource "null_resource" "ansible_provision" {
  depends_on = [ aws_instance.control_plane, aws_instance.worker_node ]

  provisioner "local-exec" {
    command = <<EOT
      sleep 50
      cat <<EOF > inventory
      [control_plane]
      control-plane-node ansible_host=${aws_instance.control_plane.public_ip} ansible_user=ubuntu ansible_become_pass=""

      [worker_nodes]
      worker-node-1 ansible_host=${aws_instance.worker_node.public_ip} ansible_user=ubuntu ansible_become_pass=""

      [all:children]
      control_plane
      worker_nodes
      EOF

      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory playbook.yml --private-key=${local_file.private_key_file.filename}
    EOT
  }
}
