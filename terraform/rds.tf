# =============================================================================
# AFFiNE AWS Terraform - RDS PostgreSQL
# =============================================================================

# -----------------------------------------------------------------------------
# DB Subnet Group
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "affine" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# -----------------------------------------------------------------------------
# DB Parameter Group (for pgvector)
# -----------------------------------------------------------------------------

resource "aws_db_parameter_group" "affine" {
  name   = "${var.project_name}-pg16-params"
  family = "postgres16"

  # Optimizations for AFFiNE workload
  # Note: shared_preload_libraries is a static param, requires reboot
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking > 1 second
  }

  tags = {
    Name = "${var.project_name}-pg-params"
  }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL Instance
# -----------------------------------------------------------------------------

resource "aws_db_instance" "affine" {
  identifier = "${var.project_name}-db"

  # Engine
  engine         = "postgres"
  engine_version = "16.4"

  # Instance
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2 # Enable storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network
  db_subnet_group_name   = aws_db_subnet_group.affine.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # Single AZ for cost savings

  # Parameter group
  parameter_group_name = aws_db_parameter_group.affine.name

  # Backup
  backup_retention_period = var.db_backup_retention
  backup_window           = "03:00-04:00" # UTC
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Monitoring
  performance_insights_enabled = false # Costs extra, enable if needed

  # Deletion protection
  deletion_protection = false # Set to true for production
  skip_final_snapshot = true  # Set to false for production

  # Apply changes immediately (for dev, use false for production)
  apply_immediately = true

  tags = {
    Name = "${var.project_name}-db"
  }
}

# -----------------------------------------------------------------------------
# Note: pgvector extension
# -----------------------------------------------------------------------------
# pgvector is installed via SQL after the instance is created.
# The user-data.sh script will run: CREATE EXTENSION IF NOT EXISTS vector;
# RDS PostgreSQL 16 supports pgvector natively.
