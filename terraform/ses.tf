# =============================================================================
# AFFiNE AWS Terraform - SES Email
# =============================================================================

# -----------------------------------------------------------------------------
# SES Domain Identity (if domain provided)
# -----------------------------------------------------------------------------

resource "aws_ses_domain_identity" "main" {
  count  = var.ses_domain != "" ? 1 : 0
  domain = var.ses_domain
}

# DKIM for domain
resource "aws_ses_domain_dkim" "main" {
  count  = var.ses_domain != "" ? 1 : 0
  domain = aws_ses_domain_identity.main[0].domain
}

# -----------------------------------------------------------------------------
# SES SMTP Credentials
# -----------------------------------------------------------------------------

# IAM user for SMTP
resource "aws_iam_user" "ses_smtp" {
  name = "${var.project_name}-ses-smtp-user"
  path = "/system/"

  tags = {
    Name = "${var.project_name}-ses-smtp-user"
  }
}

# Policy for SES sending
resource "aws_iam_user_policy" "ses_smtp" {
  name = "${var.project_name}-ses-smtp-policy"
  user = aws_iam_user.ses_smtp.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

# SMTP credentials
resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}

# -----------------------------------------------------------------------------
# Outputs for SES configuration
# -----------------------------------------------------------------------------

output "ses_smtp_username" {
  description = "SES SMTP username (use this as MAILER_USER)"
  value       = aws_iam_access_key.ses_smtp.id
}

output "ses_smtp_password" {
  description = "SES SMTP password (use this as MAILER_PASSWORD)"
  value       = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
  sensitive   = true
}

output "ses_dns_records" {
  description = "DNS records to add for SES domain verification"
  value = var.ses_domain != "" ? {
    verification_token = aws_ses_domain_identity.main[0].verification_token
    dkim_tokens        = aws_ses_domain_dkim.main[0].dkim_tokens
    instructions       = <<-EOT
      Add these DNS records to verify your domain:

      1. TXT Record for domain verification:
         Name: _amazonses.${var.ses_domain}
         Value: ${aws_ses_domain_identity.main[0].verification_token}

      2. CNAME Records for DKIM (add all 3):
         ${join("\n         ", [for token in aws_ses_domain_dkim.main[0].dkim_tokens : "${token}._domainkey.${var.ses_domain} → ${token}.dkim.amazonses.com"])}

      3. After adding records, verify in AWS Console → SES → Verified Identities
    EOT
  } : null
}
