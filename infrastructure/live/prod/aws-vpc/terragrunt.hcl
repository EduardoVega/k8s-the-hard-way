terraform {
  source = "git@github.com:EduardoVega/k8s-the-hard-way.git//infrastructure/modules/aws-vpc?ref=v1.0.0"
}

include {
  path = find_in_parent_folders()
}