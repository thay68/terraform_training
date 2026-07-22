# =============================================================================
# PROD ENVIRONMENT
# Tighter access controls, larger sizing, no auto-anything without approval
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "myproject-terraform-state-566307772614"
    key    = "prod/terraform.tfstate" # Separate state file from dev and staging
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
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "environment" {
  source = "../../modules/environment"

  environment  = "prod"
  project_name = "myproject"
  aws_region   = "us-east-1"

  # Prod gets its own non-overlapping CIDR space
  vpc_cidr            = "10.2.0.0/16"
  public_subnet_cidr  = "10.2.1.0/24"
  private_subnet_cidr = "10.2.2.0/24"
  availability_zone   = "us-east-1c"

  # Prod: properly sized — adjust based on actual workload
  instance_type   = "t3.medium"
  ami_id          = "ami-0c02fb55956c7d316"
  key_pair_name   = "terraform_key_pair"
  create_key_pair = true
  public_key_path = "/root/.ssh"

  # Prod: SSH locked to a specific bastion or VPN IP only
  # Never 0.0.0.0/0 in prod — ideally disable SSH entirely and use SSM Session Manager
  allowed_ssh_cidr = "10.2.0.0/16" # Internal VPC only — use SSM instead of SSH
  allowed_app_cidr = "0.0.0.0/0"

  extra_tags = {
    CostCenter    = "engineering-prod"
    BackupEnabled = "true"
    Compliance    = "required"
  }
}

output "instance_id" { value = module.environment.instance_id }
output "instance_public_ip" { value = module.environment.instance_public_ip }
output "ssm_command_example" { value = module.environment.ssm_command_example }
