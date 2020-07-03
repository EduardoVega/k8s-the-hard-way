# Providers
provider "aws" {
  version   = "~> 2.0"
  region    = "us-east-1"
}

terraform {
  backend "s3" {}
}

# Variables
variable "key-name" {
  type          = string
  description   = "SSH Private Key name"
}

variable "vpc-id" {
  type          = string
  description   = "VPC ID"
}

variable "control-plane-security-group-id" {
  type    = string
  description = "Security Group ID used by the Control Plane nodes"
}

variable "worker-security-group-id" {
  type    = string
  description = "Security Group ID used by the Worker nodes"
}

variable "control-plane-subnet-ids" {
  type    = list(string)
  description = "Subnets IDs used by the Control Plane nodes"
}

variable "worker-subnet-ids" {
  type    = list(string)
  description = "Subnets IDs used by the Worker nodes"
}

# Datasets
data "aws_ami" "ubuntu" {
  most_recent   = true
  filter {
    name        = "name"
    values      = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
  filter {
    name        = "virtualization-type"
    values      = ["hvm"]
  }
  owners        = ["099720109477"] # Canonical
}

# Resources

# Control Plane instances
resource "aws_instance" "control-plane-01" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t3.small"
  key_name                  = var.key-name
  subnet_id                 = var.control-plane-subnet-ids[0]
  vpc_security_group_ids    = [var.control-plane-security-group-id]
  root_block_device {
    volume_size             =   25
  }
  user_data                 = file("scripts/kubeadm.sh")
  tags                      = {
    Name = "control-plane-k8s-frozenmango-01"
    Project = "k8s-the-hard-way"
  }

  provisioner "file" {
    source      = "files/ssh-key.pem"
    destination = "ssh-key.pem"

    connection {
      type          = "ssh"
      user          = "ubuntu"
      private_key   = file("files/ssh-key.pem")
      host          = self.public_ip
    }
  }
}

resource "aws_instance" "control-plane-02" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t3.small"
  key_name                  = var.key-name
  subnet_id                 = var.control-plane-subnet-ids[1]
  vpc_security_group_ids    = [var.control-plane-security-group-id]
  root_block_device {
    volume_size             =   25
  }
  user_data                 = file("scripts/kubeadm.sh")
  tags                      = {
    Name = "control-plane-k8s-frozenmango-02"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_instance" "control-plane-03" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t3.small"
  key_name                  = var.key-name
  subnet_id                 = var.control-plane-subnet-ids[2]
  vpc_security_group_ids    = [var.control-plane-security-group-id]
  root_block_device {
    volume_size             =   25
  }
  user_data                 = file("scripts/kubeadm.sh")
  tags                      = {
    Name = "control-plane-k8s-frozenmango-03"
    Project = "k8s-the-hard-way"
  }
}

# Worker instances
resource "aws_instance" "worker-01" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t3.small"
  key_name                  = var.key-name
  subnet_id                 = var.worker-subnet-ids[0]
  vpc_security_group_ids    = [var.worker-security-group-id]
  root_block_device {
    volume_size             =   25
  }
  user_data                 = file("scripts/kubeadm.sh")
  tags                      = {
    Name = "worker-k8s-frozenmango-01"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_instance" "worker-02" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t3.small"
  key_name                  = var.key-name
  subnet_id                 = var.worker-subnet-ids[1]
  vpc_security_group_ids    = [var.worker-security-group-id]
  root_block_device {
    volume_size             =   25
  }
  user_data                 = file("scripts/kubeadm.sh")
  tags                      = {
    Name = "worker-k8s-frozenmango-02"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_instance" "worker-03" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t3.small"
  key_name                  = var.key-name
  subnet_id                 = var.worker-subnet-ids[2]
  vpc_security_group_ids    = [var.worker-security-group-id]
  root_block_device {
    volume_size             =   25
  }
  user_data                 = file("scripts/kubeadm.sh")
  tags                      = {
    Name = "worker-k8s-frozenmango-03"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_lb" "control-plane" {
  name               = "k8s-frozenmango"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.control-plane-subnet-ids

  tags = {
    Name = "k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_lb_target_group" "control-plane" {
  name     = "k8s-frozenmango"
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.vpc-id

  tags = {
    Name = "k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_lb_target_group_attachment" "control-plane-01" {
  target_group_arn = aws_lb_target_group.control-plane.arn
  target_id        = aws_instance.control-plane-01.id
  port             = 6443
}

resource "aws_lb_target_group_attachment" "control-plane-02" {
  target_group_arn = aws_lb_target_group.control-plane.arn
  target_id        = aws_instance.control-plane-02.id
  port             = 6443
}

resource "aws_lb_target_group_attachment" "control-plane-03" {
  target_group_arn = aws_lb_target_group.control-plane.arn
  target_id        = aws_instance.control-plane-03.id
  port             = 6443
}

resource "aws_lb_listener" "control-plane" {
  load_balancer_arn = aws_lb.control-plane.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.control-plane.arn
  }
}

# Outputs
output "control-plane-instance-01-id" {
  value       =  aws_instance.control-plane-01.id
  description = "Control Plane instance 01 ID"
}

output "control-plane-instance-01-private-ip" {
  value       =  aws_instance.control-plane-01.private_ip
  description = "Control Plane instance 01 Private IP"
}

output "control-plane-instance-01-public-ip" {
  value       =  aws_instance.control-plane-01.public_ip
  description = "Control Plane instance 01 Public IP"
}

output "control-plane-instance-02-id" {
  value       =  aws_instance.control-plane-02.id
  description = "Control Plane instance 02 ID"
}

output "control-plane-instance-02-private-ip" {
  value       =  aws_instance.control-plane-02.private_ip
  description = "Control Plane instance 02 Private IP"
}

output "control-plane-instance-02-public-ip" {
  value       =  aws_instance.control-plane-02.public_ip
  description = "Control Plane instance 02 Public IP"
}

output "control-plane-instance-03-id" {
  value       =  aws_instance.control-plane-03.id
  description = "Control Plane instance 03 ID"
}

output "control-plane-instance-03-private-ip" {
  value       =  aws_instance.control-plane-03.private_ip
  description = "Control Plane instance 03 Private IP"
}

output "control-plane-instance-03-public-ip" {
  value       =  aws_instance.control-plane-03.public_ip
  description = "Control Plane instance 03 Public IP"
}

output "worker-instance-01-id" {
  value       =  aws_instance.worker-01.id
  description = "Worker instance 01 ID"
}

output "worker-instance-01-private-ip" {
  value       =  aws_instance.worker-01.private_ip
  description = "Worker instance 01 Private IP"
}

output "worker-instance-02-id" {
  value       =  aws_instance.worker-02.id
  description = "Worker instance 02 ID"
}

output "worker-instance-02-private-ip" {
  value       =  aws_instance.worker-02.private_ip
  description = "Worker instance 02 Private IP"
}

output "worker-instance-03-id" {
  value       =  aws_instance.worker-03.id
  description = "Worker instance 03 ID"
}

output "worker-instance-03-private-ip" {
  value       =  aws_instance.worker-03.private_ip
  description = "Worker instance 03 Private IP"
}

output "load-balancer-domain-name" {
  value = aws_lb.control-plane.dns_name 
  description = "Load Balancer Domain Name"
}