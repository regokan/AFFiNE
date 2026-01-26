# =============================================================================
# AFFiNE AWS Terraform - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "affine"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (your IP, e.g., 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0" # WARNING: Restrict this to your IP!
}

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small" # 2 vCPU, 2GB RAM - ~$15/month
}

variable "ec2_volume_size" {
  description = "EC2 root volume size in GB"
  type        = number
  default     = 30
}

variable "ec2_key_name" {
  description = "Existing EC2 key pair name (leave empty to create new)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro" # 2 vCPU, 1GB RAM - ~$15/month
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "affine"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "affine"
}

variable "db_backup_retention" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# AFFiNE Configuration
# -----------------------------------------------------------------------------

variable "affine_revision" {
  description = "AFFiNE Docker image tag (stable or canary)"
  type        = string
  default     = "stable"
}

# -----------------------------------------------------------------------------
# Email (SES)
# -----------------------------------------------------------------------------

variable "ses_domain" {
  description = "Domain for SES email (e.g., yourdomain.com)"
  type        = string
  default     = ""
}

variable "mailer_sender" {
  description = "Email sender address"
  type        = string
  default     = "AFFiNE <noreply@example.com>"
}

# -----------------------------------------------------------------------------
# Domain & SSL
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Domain name for AFFiNE (e.g., affine.example.com). Leave empty to skip HTTPS setup."
  type        = string
  default     = ""
}

variable "ssl_email" {
  description = "Email for Let's Encrypt SSL certificate notifications"
  type        = string
  default     = ""
}
