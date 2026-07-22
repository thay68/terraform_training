# =============================================================================
# DEV ENVIRONMENT
#
# Run order:
#   1. cd ../../bootstrap && terraform apply   (first time only)
#   2. cd environments/dev
#   3. terraform init     (downloads providers, configures S3 backend)
#   4. terraform plan
#   5. terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  # -----------------------------------------------------------------------------
  # REMOTE STATE + LOCKING
  #
  # State file lives at: s3://myproject-terraform-state-<account_id>/dev/terraform.tfstate
  # Lock record lives in DynamoDB table: myproject-terraform-locks
  #
  # What happens when you run terraform apply:
  #   1. Terraform reads current state from S3
  #   2. Writes a lock record to DynamoDB (LockID = s3 path)
  #   3. Plans and applies changes
  #   4. Writes updated state back to S3
  #   5. Deletes the DynamoDB lock record
  #
  # If step 2 finds an existing lock → apply fails immediately with the
  # ID of who holds the lock, so you can investigate before proceeding.
  # To manually clear a stuck lock: terraform force-unlock <lock-id>
  # -----------------------------------------------------------------------------
  backend "s3" {
    bucket = "myproject-terraform-state-566307772614" # From bootstrap output
    key    = "dev/terraform.tfstate"                  # Each env gets its own path
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
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "environment" {
  source = "../../modules/environment"

  # Identity
  environment  = "dev"
  project_name = "myproject"
  aws_region   = "us-east-1"

  # Networking — using defaults from the module variables.tf
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  availability_zone   = "us-east-1a"

  # EC2 — small and cheap in dev
  instance_type   = "t3.micro"
  ami_id          = "ami-0c02fb55956c7d316" # Amazon Linux 2023, us-east-1
  key_pair_name   = "terraform_key_pair"
  create_key_pair = true
  public_key_path = "/root/.ssh"

  # Access — wide open in dev for convenience
  allowed_ssh_cidr = "0.0.0.0/0" # Lock this down in prod!
  allowed_app_cidr = "0.0.0.0/0"

  extra_tags = {
    CostCenter   = "engineering-dev"
    AutoShutdown = "true" # Tag your dev instances for auto-shutdown scripts
  }
}

# Surface useful values after apply
output "instance_id" { value = module.environment.instance_id }
output "instance_public_ip" { value = module.environment.instance_public_ip }
output "ssm_command_example" { value = module.environment.ssm_command_example }
