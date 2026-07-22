# =============================================================================
# MODULE OUTPUTS
# Callers can reference these with module.environment.<output_name>
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "security_group_id" {
  description = "App server security group ID"
  value       = aws_security_group.app.id
}

output "instance_id" {
  description = "EC2 instance ID — use this with aws ssm send-command"
  value       = aws_instance.app.id
}

output "instance_public_ip" {
  description = "Public IP of the app server"
  value       = aws_instance.app.public_ip
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.app.arn
}

output "ssm_command_example" {
  description = "Ready-to-run SSM command to verify the instance is reachable"
  value       = "aws ssm send-command --instance-ids ${aws_instance.app.id} --document-name AWS-RunShellScript --parameters commands='echo hello from ${var.environment}' --region ${var.aws_region}"
}

output "key-pair-name" {
  value = "${aws_instance.app.key_name}"
}