# Providers
provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
}

terraform {
  backend "s3" {}
}

# Datasets
data "aws_availability_zones" "available" {
  state = "available"
}

# Resources

# VPC
resource "aws_vpc" "main" {
  cidr_block                = "10.0.0.0/16"
  enable_dns_hostnames      = true

  tags = {
    Name = "k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

# VPC configuration for Master nodes
resource "aws_subnet" "public" {
  count = 3

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = aws_vpc.main.id
  map_public_ip_on_launch = true

  tags = {
    Name = "public-k8s-frozenmango-${count.index}"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public.id
  }

  tags = {
    Name = "internet-k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.public.id
}

# VPC configuration for Workers nodes
resource "aws_subnet" "private" {
  count = 3

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index + 10}.0/24"
  vpc_id            = aws_vpc.main.id

  tags = {
    Name = "private-k8s-frozenmango-${count.index}"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_eip" "private" {
  vpc = true

  tags = {
    Name = "k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }

  depends_on = [ aws_internet_gateway.public ]
}

resource "aws_nat_gateway" "private" {
  allocation_id = aws_eip.private.id
  subnet_id     = aws_subnet.public.*.id[0]

  tags = {
    Name = "k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.private.id
  }

  tags = {
    Name = "nat-k8s-frozenmango"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private.*.id[count.index]
  route_table_id = aws_route_table.private.id
}

# Security Group configuration for Control Plane Nodes
resource "aws_security_group" "control-plane" {
  name        = "Control Plane Security Group"
  description = "Control Plane Port access configuration"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-frozenmango-control-plane"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_security_group_rule" "control-plane-ssh" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow SSH access to control plane nodes"
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.control-plane.id
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group_rule" "control-plane-apiserver" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all access to kube api server port"
  from_port         = 6443
  protocol          = "tcp"
  security_group_id = aws_security_group.control-plane.id
  to_port           = 6443
  type              = "ingress"
}

resource "aws_security_group_rule" "control-plane-etcd" {
  description              = "Allow access to etcd server from api server and etcd"
  from_port                = 2379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control-plane.id
  source_security_group_id = aws_security_group.control-plane.id
  to_port                  = 2380
  type                     = "ingress"
}

resource "aws_security_group_rule" "control-plane-kubelet-scheduler-controller" {
  description              = "Allow communication to kubelet api, kube-scheduler, kube-controller-manager from control-plane nodes"
  from_port                = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control-plane.id
  source_security_group_id = aws_security_group.control-plane.id
  to_port                  = 10252
  type                     = "ingress"
}

# Security Group configuration for Worker nodes
resource "aws_security_group" "worker" {
  name        = "Worker Nodes Security Group"
  description = "Worker Nodes Port access configuration"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-frozenmango-worker"
    Project = "k8s-the-hard-way"
  }
}

resource "aws_security_group_rule" "worker-ssh" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow SSH access to worker nodes"
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.worker.id
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group_rule" "worker-kubelet" {
  description              = "Allow communication between control plane nodes to worker nodes kubelet api"
  from_port                = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.control-plane.id
  to_port                  = 10250
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker-kubelet-worker" {
  description              = "Allow communication between worker nodes through kubelet api"
  from_port                = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.worker.id
  to_port                  = 10250
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker-node-ports" {
  description              = "Allow communication to all ports used by NodePort services"
  from_port                = 30000
  protocol                 = "-1"
  security_group_id        = aws_security_group.worker.id
  cidr_blocks              = ["0.0.0.0/0"]
  to_port                  = 32767
  type                     = "ingress"
}

# Outputs
output "vpc-id" {
  value       =  aws_vpc.main.id
  description = "VPC ID"
}

output "public-subnet-ids" {
  value       =  aws_subnet.public.*.id
  description = "Public subnet IDs"
}

output "private-subnet-ids" {
  value       =  aws_subnet.private.*.id
  description = "Private subnet IDs"
}

output "control-plane-security-group-id" {
  value       =  aws_security_group.control-plane.id
  description = "Control Plane security group ID"
}

output "worker-security-group-id" {
  value       =  aws_security_group.worker.id
  description = "Workers security group id"
}