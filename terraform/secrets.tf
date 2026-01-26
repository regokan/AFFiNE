# =============================================================================
# AFFiNE AWS Terraform - Secrets Manager
# Backup of sensitive values that aren't in version control
# =============================================================================

resource "aws_secretsmanager_secret" "affine" {
  name        = "${var.project_name}-secrets"
  description = "AFFiNE deployment secrets backup"

  tags = {
    Name = "${var.project_name}-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "affine" {
  secret_id = aws_secretsmanager_secret.affine.id
  secret_string = jsonencode({
    db_password       = var.db_password
    db_username       = var.db_username
    db_host           = aws_db_instance.affine.address
    database_url      = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.affine.address}:5432/${var.db_name}"
    ses_smtp_username = aws_iam_access_key.ses_smtp.id
    ses_smtp_password = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
    domain_name       = var.domain_name
    ses_domain        = var.ses_domain
  })
}
