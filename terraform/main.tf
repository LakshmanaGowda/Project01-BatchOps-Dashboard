terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "devops_lab" {
  ami                    = "ami-006f82a1d5a27da54"
  instance_type          = "t2.micro"
  subnet_id              = "subnet-0f3dbd5a28ea28ef8"
  vpc_security_group_ids = ["sg-0628249d40dd451dc"]
  key_name               = "devops-key"

  tags = {
    Name = "devops-lab-server"
  }
}