# =============================================================================
# MODULE VARIABLES
# These are the knobs callers (dev/staging/prod) turn to parameterize the module
# =============================================================================

variable "environment" {
  description = "Environment name — drives naming and sizing decisions"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "project_name" {
  description = "Short project name, used in all resource names"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# VPC / Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AZ to place subnets in"
  type        = string
  default     = "us-east-1a"
}

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type — typically smaller in dev, larger in prod"
  type        = string
  # No default — callers must be explicit about this
}

variable "ami_id" {
  description = "AMI ID to launch — Amazon Linux 2023 recommended"
  type        = string
}

variable "key_pair_name" {
  description = "Base name of the EC2 key pair for SSH access; the environment will be appended"
  type        = string
  default     = "terraform_key_pair"
}

variable "create_key_pair" {
  description = "Whether to create the EC2 key pair if it does not already exist"
  type        = bool
  default     = true
}

variable "public_key_path" {
  description = "Path to a public key file to use when creating the EC2 key pair"
  type        = string
  default     = null
}

variable "public_key_material" {
  description = "Raw public key content to use when creating the EC2 key pair"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Access control
# -----------------------------------------------------------------------------
variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to the instance. Lock this down — never 0.0.0.0/0 in prod"
  type        = string
  default     = "10.0.0.0/8"  # Private ranges only by default
}

variable "allowed_app_cidr" {
  description = "CIDR allowed to reach the app port (8080)"
  type        = string
  default     = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# Tags passed in from the calling environment
# Merged with tags the module sets automatically
# -----------------------------------------------------------------------------
variable "extra_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
