# =============================================================================
# AFFiNE AWS Terraform - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------

output "ec2_public_ip" {
  description = "Public IP address of EC2 instance"
  value       = aws_eip.affine.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.affine.id
}

output "affine_url" {
  description = "URL to access AFFiNE"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_eip.affine.public_ip}:3010"
}

output "ssh_command" {
  description = "SSH command to connect to EC2"
  value       = var.ec2_key_name != "" ? "ssh -i ~/.ssh/${var.ec2_key_name}.pem ec2-user@${aws_eip.affine.public_ip}" : "ssh -i ${local_file.private_key[0].filename} ec2-user@${aws_eip.affine.public_ip}"
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.affine.endpoint
}

output "rds_hostname" {
  description = "RDS PostgreSQL hostname"
  value       = aws_db_instance.affine.address
}

output "database_url" {
  description = "PostgreSQL connection URL (sensitive)"
  value       = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.affine.address}:5432/${var.db_name}"
  sensitive   = true
}

# -----------------------------------------------------------------------------
# SES
# -----------------------------------------------------------------------------

output "ses_smtp_endpoint" {
  description = "SES SMTP endpoint"
  value       = "email-smtp.${var.aws_region}.amazonaws.com"
}

output "ses_verification_status" {
  description = "SES domain verification status (if domain provided)"
  value       = var.ses_domain != "" ? "Check AWS Console for DNS records to add" : "No domain configured"
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# -----------------------------------------------------------------------------
# Quick Start
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT

    ============================================================
    AFFiNE Deployment Complete!
    ============================================================

    1. Access AFFiNE:
       ${var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_eip.affine.public_ip}:3010"}

    2. SSH to server:
       ${var.ec2_key_name != "" ? "ssh -i ~/.ssh/${var.ec2_key_name}.pem ec2-user@${aws_eip.affine.public_ip}" : "ssh -i affine-key.pem ec2-user@${aws_eip.affine.public_ip}"}

    3. View logs:
       docker logs -f affine_server

    ${var.domain_name != "" ? "4. SSL is auto-configured with Let's Encrypt\n       Certificate auto-renews via systemd timer" : "4. For HTTPS, set domain_name in terraform.tfvars"}

    5. Configure email (REQUIRED for user verification):
       a) Get SMTP credentials:
          terraform output ses_smtp_username
          terraform output -raw ses_smtp_password
       
       b) SSH to EC2 and edit /opt/affine/.env:
          - Set MAILER_USER=<ses_smtp_username>
          - Set MAILER_PASSWORD=<ses_smtp_password>
       
       c) Recreate: cd /opt/affine && sudo docker compose up -d --force-recreate affine

    ============================================================
  EOT
}
