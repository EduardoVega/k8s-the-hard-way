terraform {
  source = "git@github.com:EduardoVega/k8s-the-hard-way.git//infrastructure/modules/aws-ec2?ref=v1.0.0"
}

include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../aws-vpc"
}

inputs = {
  key-name = "ec2-vms"
  vpc-id = dependency.vpc.outputs.vpc-id
  control-plane-security-group-id = dependency.vpc.outputs.control-plane-security-group-id
  control-plane-subnet-ids = dependency.vpc.outputs.public-subnet-ids
  worker-security-group-id = dependency.vpc.outputs.worker-security-group-id
  worker-subnet-ids = dependency.vpc.outputs.private-subnet-ids
}