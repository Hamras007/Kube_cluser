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








# VPC
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k8s-vpc"
  }
}

# Subnets
resource "aws_subnet" "k8s_subnet_public" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  availability_zone       = "ap-south-1b"    
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet-public"
  }
}

resource "aws_subnet" "k8s_subnet_public_A" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  availability_zone       = "ap-south-1a"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet-public-A"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

# Route Table
resource "aws_route_table" "k8s_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "k8s_rta" {
  subnet_id      = aws_subnet.k8s_subnet_public.id
  route_table_id = aws_route_table.k8s_rt.id
}











# Security Group for Kubernetes
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-security-group"
  description = "Allow necessary traffic for Kubernetes cluster"
  vpc_id      = aws_vpc.k8s_vpc.id

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
  ami           = "ami-09b0a86a2c84101e1" 
  instance_type = "t2.medium"
  key_name      = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]  
  availability_zone = "ap-south-1b"
  subnet_id          = aws_subnet.k8s_subnet_public.id   

  tags = {
    Name = "k8s-control-plane"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
    delete_on_termination = true
}
}









# Create Application Load Balancer (NLB)
resource "aws_lb" "k8s_nlb" {
  name               = "k8s-nlb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.k8s_subnet_public.id, aws_subnet.k8s_subnet_public_A.id] 

  enable_deletion_protection = false

  tags = {
    Name = "k8s-nlb"
  }
}

# Create NLB Target Group
resource "aws_lb_target_group" "k8s_nlb_target_group" {
  name        = "k8s-nlb-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.k8s_vpc.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    protocol            = "HTTP"
  }

  tags = {
    Name = "k8s-nlb-target-group"
  }
}

# Create NLB Listener
resource "aws_lb_listener" "k8s_nlb_listener" {
  load_balancer_arn = aws_lb.k8s_nlb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_nlb_target_group.arn
  }
}









resource "aws_launch_template" "worker_node_template" {
  name_prefix   = "k8s-worker-node-template"
  image_id      = "ami-09b0a86a2c84101e1" # Debian AMI ID
  instance_type = "t2.medium"
  key_name      = aws_key_pair.k8s_key.key_name

  network_interfaces {
    security_groups = [aws_security_group.k8s_sg.id]
    associate_public_ip_address = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp2"
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "k8s-worker-node"
    }
  }
}

# Update Auto Scaling Group to use Launch Template
resource "aws_autoscaling_group" "worker_node_asg" {
  desired_capacity          = 2
  max_size                  = 5
  min_size                  = 1
  vpc_zone_identifier       = [aws_subnet.k8s_subnet_public.id]
  launch_template {
    id      = aws_launch_template.worker_node_template.id
    version = "$Latest"
  }
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true
  wait_for_capacity_timeout = "0"

#target_group_arns = [aws_lb_target_group.k8s_nlb_target_group.arn]

  tag {
    key                 = "Name"
    value               = "k8s-worker-node"
    propagate_at_launch = true
  }
}





resource "null_resource" "asg_ready" {

depends_on = [aws_autoscaling_group.worker_node_asg]
provisioner "local-exec" {
command = "sleep 50"
}
}


data "aws_instances" "asg" {
  
  filter {
    name   = "instance-state-name"  
    values = ["running"]           
  }

filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.worker_node_asg.name]
  }


depends_on = [null_resource.asg_ready]
}




# OUTPUTS_BEGIN

output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip

}

output "worker_node_ip_1" {
  value = element(data.aws_instances.asg.public_ips, 0)
}

output "worker_node_ip_2" {
  value = element(data.aws_instances.asg.public_ips, 1)
}

output "lb_dns" {
  value = aws_lb.k8s_nlb.dns_name

}

output "private_key" {
  value     = tls_private_key.k8s_key.private_key_pem
  sensitive = true
}

# OUTPUTS_END

locals {
  worker_node_publicip_1 = element(data.aws_instances.asg.public_ips, 0)
  worker_node_publicip_2 = element(data.aws_instances.asg.public_ips, 1)
}









# Create the Ansible inventory dynamically
data "template_file" "inventory" {
  template = <<EOT
[control_plane]
control-plane-node ansible_host=${aws_instance.control_plane.public_ip} ansible_user=ubuntu ansible_become_pass=""

[worker_nodes]
worker-node-1 ansible_host=${local.worker_node_publicip_1} ansible_user=ubuntu ansible_become_pass=""
worker-node-2 ansible_host=${local.worker_node_publicip_2} ansible_user=ubuntu ansible_become_pass=""

[all:children]
control_plane
worker_nodes
EOT
}








# Save Inventory File Locally
resource "local_file" "inventory" {
  content  = data.template_file.inventory.rendered
  filename = "${path.module}/inventory"
}


output "ansible_inventory" {
  value = local_file.inventory.content
  description = "The content of the Ansible inventory file"
}

resource "null_resource" "ansible_provision" {
  depends_on = [ aws_instance.control_plane, aws_autoscaling_group.worker_node_asg, aws_lb.k8s_nlb ] 
  provisioner "local-exec" {

    command= "sleep 10 && ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ${local_file.inventory.filename} playbook.yml --private-key=${local_file.private_key_file.filename}"
  }
}

resource "null_resource" "kube_conf_retrieve" {
  depends_on = [null_resource.ansible_provision]
  provisioner "remote-exec" {

 inline = [
      "sudo mkdir -p /etc/kubernetes",
      "sudo cp /etc/kubernetes/admin.conf /home/ubuntu/admin.conf",
      "sudo chmod 777 /home/ubuntu/admin.conf"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu" # Update this as per your AMI
      private_key = file(local_file.private_key_file.filename)
      host        = aws_instance.control_plane.public_ip
    }

    on_failure = continue
}
}

resource "null_resource" "copy_admin_conf" {
  depends_on = [null_resource.kube_conf_retrieve]

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ${local_file.private_key_file.filename} ubuntu@${aws_instance.control_plane.public_ip}:/home/ubuntu/admin.conf ${path.module}/"
  }
}

