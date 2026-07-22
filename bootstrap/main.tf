# =============================================================================
# BOOTSTRAP — run this ONCE before anything else
#
# Creates the S3 bucket and DynamoDB table that all environments use
# for remote state and locking. This is the chicken-and-egg problem of
# Terraform: you need infra to store state, but you need state to manage infra.
# Solution: bootstrap uses LOCAL state only (no backend block), and you
# commit the resulting tfstate file or just leave it local.
#
# Usage:
#   cd bootstrap/
#   terraform init
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Intentionally NO backend block — this one stays local
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to create the state bucket in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used to namespace all resources"
  type        = string
  default     = "myproject"
}

# -----------------------------------------------------------------------------
# S3 bucket — stores all environment state files
# Each environment gets its own key (path) inside this single bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion of state
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "Terraform State"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"   # Lets you roll back to a previous state if something goes wrong
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# DynamoDB table — provides the distributed lock
#
# How locking works:
#   1. Before apply, Terraform writes a record to this table (the "lock")
#   2. If another process tries to apply at the same time, it sees the lock
#      and fails immediately with a clear error instead of corrupting state
#   3. After apply completes (or on terraform force-unlock), the record is deleted
#
# The table only needs one attribute: LockID (string) as the partition key.
# Terraform handles everything else automatically.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"  # No need to provision capacity for occasional lock ops
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "Terraform State Locks"
    Project = var.project_name
  }
}

data "aws_caller_identity" "current" {}

output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "Paste this into the backend config of each environment"
}

output "lock_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "Paste this into the backend config of each environment"
}
