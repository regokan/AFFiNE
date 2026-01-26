# =============================================================================
# AFFiNE AWS Terraform - EC2 Instance
# =============================================================================

# -----------------------------------------------------------------------------
# SSH Key Pair (create new if not provided)
# -----------------------------------------------------------------------------

resource "tls_private_key" "affine" {
  count     = var.ec2_key_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "affine" {
  count      = var.ec2_key_name == "" ? 1 : 0
  key_name   = "${var.project_name}-key-${random_id.suffix.hex}"
  public_key = tls_private_key.affine[0].public_key_openssh

  tags = {
    Name = "${var.project_name}-key"
  }
}

# Save private key locally
resource "local_file" "private_key" {
  count           = var.ec2_key_name == "" ? 1 : 0
  content         = tls_private_key.affine[0].private_key_pem
  filename        = "${path.module}/affine-key.pem"
  file_permission = "0600"
}

# -----------------------------------------------------------------------------
# IAM Role for EC2
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# Allow EC2 to send emails via SES
resource "aws_iam_role_policy" "ec2_ses" {
  name = "${var.project_name}-ec2-ses-policy"
  role = aws_iam_role.ec2.id

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

# Allow EC2 to pull from ECR (for future use)
resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Allow SSM for easier management (optional)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "affine" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_name != "" ? var.ec2_key_name : aws_key_pair.affine[0].key_name
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ec2_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    db_host         = aws_db_instance.affine.address
    db_port         = "5432"
    db_name         = var.db_name
    db_username     = var.db_username
    db_password     = var.db_password
    affine_revision = var.affine_revision
    aws_region      = var.aws_region
    mailer_sender   = var.mailer_sender
    domain_name     = var.domain_name
    ssl_email       = var.ssl_email
    openai_api_key  = var.openai_api_key
  }))

  tags = {
    Name = "${var.project_name}-server"
  }

  # Wait for RDS to be ready before launching EC2
  depends_on = [aws_db_instance.affine]
}

# -----------------------------------------------------------------------------
# Elastic IP (static public IP)
# -----------------------------------------------------------------------------

resource "aws_eip" "affine" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

resource "aws_eip_association" "affine" {
  instance_id   = aws_instance.affine.id
  allocation_id = aws_eip.affine.id
}
