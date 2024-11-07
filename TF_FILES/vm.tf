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
  region  = var.region
}

resource "aws_key_pair" "deployer" {
  key_name   = "my_new_ssh_pbkey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCfqYUnn7D+XsHR7WHB5oG6GDOJDn/vzqb6VpcWhDHxvYSHDHN+ZK9Frugw4vz88h+eR1FClVz/CGH/jiXroN+1djHt9SH7E5gdh5f9KXRB6BJ3owvxT0hSK4N1t8ryNbo8Z74vDjUB0hqf9tKAODxHPWbC6BUGr6u2PGmzztGQMDJOKSk15YppeuCJbUdDsSzyUfEQD1riuJ/8I//RL8cNG3p0ZkLlEKFEo7lN5QaFEJbd9PfWm0z6ajMNZO52AtWaRYYqsq0XJeABiSQ2Z+2NrBv2+WzzWllPHAlaiJeLrNq27rp1PykhCqF/JTO6BZvZGt6H9fCiITqFDgkmIJW7hkcjl+hPV7MBBuT8wo4jfKa/0nV5HrWor8LbtUEXxow+QsCrHmqv6UciclrokGuwozk8RoQ0lKSo3cgllNZl+auGEPhhSeCTiNpjl01RQMhEz5QdnJSD3IfI8FtRGUKLYwbeUjSWqNyxNsn0mfKDukvyQ855CouK1Y5qLzAKZ68= root@master"
}

resource "aws_security_group" "ssh-sg" {
  name = "my_new_ssh_sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  count = 1
  key_name = "my_new_ssh_pbkey"
  vpc_security_group_ids = [aws_security_group.my_new_ssh_sg.id]

  tags = {
    Name = "app_server"
  }
  provisioner "remote-exec" {
    inline = ["sudo apt update", "sudo apt install python3 -y", "sudo apt install nginx -y", "echo Done!"]
    connection {
      host        = self.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
    }
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${self.public_ip},' apache-ansible.yml"
  }
}