terraform {
  required_providers {
    # https://registry.terraform.io/providers/hashicorp/aws/latest/docs
    aws = {
      source = "hashicorp/aws"
      version = "5.82.2"
    }
  }
}

# Configure the aws provider
provider "aws" {
  region = "eu-west-1"
}
