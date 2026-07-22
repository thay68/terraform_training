# =============================================================================
# ENVIRONMENT MODULE
# Provisions one complete environment: VPC, subnets, IGW, NAT, route tables,
# security group, IAM role + instance profile, and an EC2 instance.
#
# Called by environments/dev, environments/staging, environments/prod —
# each passes different variable values; this file never changes.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Merge caller-supplied tags with tags this module always sets
locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.extra_tags
  )
  name_prefix = "${var.project_name}-${var.environment}"
  key_pair_name = "${var.key_pair_name}-${var.environment}"

  resolved_public_key_path = var.public_key_path != null && var.public_key_path == "/root/.ssh" ? "${var.public_key_path}/${local.key_pair_name}.pub" : var.public_key_path
  fallback_public_key_path = var.public_key_path != null && var.public_key_path == "/root/.ssh" ? "/root/.ssh/id_rsa.pub" : null

  public_key_value = try(
    local.resolved_public_key_path != null && fileexists(local.resolved_public_key_path) ? file(local.resolved_public_key_path) : (
      local.fallback_public_key_path != null && fileexists(local.fallback_public_key_path) ? file(local.fallback_public_key_path) : (
        var.public_key_material != null ? var.public_key_material : try(tls_private_key.app[0].public_key_openssh, null)
      )
    ),
    try(tls_private_key.app[0].public_key_openssh, null)
  )
}

# =============================================================================
# VPC
# =============================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true   # Needed for SSM agent to resolve endpoints

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

# =============================================================================
# SUBNETS
# Public: has a route to the internet gateway — load balancers, bastion hosts
# Private: has a route to the NAT gateway — app servers, databases
# =============================================================================
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true   # Instances here get a public IP automatically

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private" })
}

# =============================================================================
# INTERNET GATEWAY — the VPC's front door for two-way internet traffic
# Attach one per VPC; public subnets route through it
# =============================================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

# =============================================================================
# NAT GATEWAY — sits in the public subnet, gives private subnet one-way
# outbound internet access (e.g. to download packages, call external APIs)
# Needs an Elastic IP so it has a stable public IP address
# =============================================================================
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id   # NAT gateway lives in the PUBLIC subnet

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# ROUTE TABLES
# Public: 0.0.0.0/0 → internet gateway
# Private: 0.0.0.0/0 → NAT gateway
# This single line difference is what makes a subnet "public" or "private"
# =============================================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rt-public" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rt-private" })
}

# Associate each subnet with its route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# SECURITY GROUP
# Stateful — return traffic is automatically allowed, so you only write
# inbound rules for what you want to accept, and outbound for what you
# want the instance to be able to initiate
# =============================================================================
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "App server security group for ${var.environment}"
  vpc_id      = aws_vpc.main.id

  # SSH — locked to allowed CIDR (never 0.0.0.0/0 in prod)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # App port
  ingress {
    description = "App traffic"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_app_cidr]
  }

  # HTTPS inbound (e.g. if behind a load balancer)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound allowed — instance can call AWS APIs, download packages, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-sg" })
}

# =============================================================================
# IAM ROLE + INSTANCE PROFILE
# Lets EC2 instances call AWS APIs without hardcoded credentials —
# the same principle as your Oracle service accounts but handled by AWS STS
#
# SSM policy is the critical one: lets you run commands on the instance via
# AWS Systems Manager (aws ssm send-command) without opening SSH port at all
# =============================================================================
resource "aws_iam_role" "app" {
  name        = "${local.name_prefix}-app-role"
  description = "Role for ${var.environment} app servers"

  # Trust policy: only EC2 service can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# SSM managed policy — enables Systems Manager fleet operations (your Week 2 script)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent policy — enables metrics/log shipping (ties into Week 7 monitoring)
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Inline policy: S3 read access scoped to this environment's prefix only
# Least privilege — prod role can't read dev bucket and vice versa
resource "aws_iam_role_policy" "s3_access" {
  name = "${local.name_prefix}-s3-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.project_name}-${var.environment}-*",
        "arn:aws:s3:::${var.project_name}-${var.environment}-*/*"
      ]
    }]
  })
}

# Instance profile wraps the role so EC2 can use it
resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
  tags = local.common_tags
}

resource "tls_private_key" "app" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create the EC2 key pair when requested.
resource "aws_key_pair" "app" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = local.key_pair_name
  public_key = local.public_key_value
}

# =============================================================================
# EC2 INSTANCE
# Placed in the PUBLIC subnet here for simplicity — in a real prod setup
# you'd put app servers in the private subnet behind a load balancer
# =============================================================================
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = local.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.app.name

  depends_on = [aws_key_pair.app]

  # User data: bootstrap script that runs on first launch
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    yum update -y
    # Install SSM agent (included in Amazon Linux 2023, but explicit is safer)
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    # Tag this instance's hostname with environment for easy identification
    hostnamectl set-hostname ${local.name_prefix}-app
  EOF
  )

  root_block_device {
    volume_size           = var.environment == "prod" ? 50 : 20   # Bigger disk in prod
    volume_type           = "gp3"
    encrypted             = true   # Always encrypt — no reason not to
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app"
    Role = "app-server"
  })
}
