# =============================================================================
# STAGING ENVIRONMENT
# Mirrors prod sizing where possible to catch environment-specific bugs
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "myproject-terraform-state-566307772614"
    key    = "staging/terraform.tfstate" # Different key = separate state file
    region = "us-east-1"
    # dynamodb_table = "myproject-terraform-locks"                # From bootstrap output
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

module "environment" {
  source = "../../modules/environment"

  environment  = "staging"
  project_name = "myproject"
  aws_region   = "us-east-1"

  # Different CIDR ranges per environment avoids overlap if you ever VPC-peer them
  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidr  = "10.1.1.0/24"
  private_subnet_cidr = "10.1.2.0/24"
  availability_zone   = "us-east-1b"

  # Staging: mid-sized — enough to surface memory/CPU issues that t3.micro would hide
  instance_type   = "t3.small"
  ami_id          = "ami-0c02fb55956c7d316"
  key_pair_name   = "terraform_key_pair"
  create_key_pair = true
  public_key_path = "/root/.ssh"

  # Access — SSH locked to your office/VPN CIDR in staging
  allowed_ssh_cidr = "203.0.113.0/24" # Replace with your actual IP/CIDR
  allowed_app_cidr = "0.0.0.0/0"

  extra_tags = {
    CostCenter = "engineering-staging"
  }
}

output "instance_id" { value = module.environment.instance_id }
output "instance_public_ip" { value = module.environment.instance_public_ip }
output "ssm_command_example" { value = module.environment.ssm_command_example }
