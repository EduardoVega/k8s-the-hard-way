remote_state {
  backend = "s3"
  config = {
    bucket         = "k8s-frozenmango-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "k8s-frozenmango-terraform-lock-table"
    s3_bucket_tags = {
        Project = "k8s-frozenmango"
    }
    dynamodb_table_tags = {
        Project = "k8s-frozenmango"
    }
  }
}