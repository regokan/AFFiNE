# AFFiNE AWS Terraform Deployment

This Terraform configuration deploys AFFiNE on AWS with a cost-effective setup.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Public Subnet                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              EC2 (t3.small)                     │  │  │
│  │  │  ┌─────────────────┐  ┌──────────────────────┐ │  │  │
│  │  │  │  AFFiNE Server  │  │   Redis (Docker)     │ │  │  │
│  │  │  │    (Docker)     │  │                      │ │  │  │
│  │  │  └─────────────────┘  └──────────────────────┘ │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                          │                             │  │
│  │                          ▼                             │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                   Private Subnet                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │         RDS PostgreSQL (t3.micro)               │  │  │
│  │  │              with pgvector                      │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │    AWS SES      │
                    │  (Email SMTP)   │
                    └─────────────────┘
```

## Cost Estimate (~$30-50/month)

| Resource       | Type        | Estimated Cost            |
| -------------- | ----------- | ------------------------- |
| EC2            | t3.small    | ~$15/month                |
| RDS PostgreSQL | t3.micro    | ~$15/month                |
| Elastic IP     | 1           | ~$4/month (when attached) |
| SES            | Pay per use | ~$0.10/1000 emails        |
| Data Transfer  | Variable    | ~$1-5/month               |

## Prerequisites

1. **AWS CLI** installed and configured
2. **Terraform** >= 1.0 installed
3. **Domain** (optional, for SES email)

## Quick Start

### 1. Configure Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region      = "us-east-1"
project_name    = "affine"
environment     = "production"

# Your public IP for SSH access (find at: https://whatismyip.com)
allowed_ssh_cidr = "YOUR_IP/32"

# Database
db_username = "affine"
db_password = "CHANGE_THIS_SECURE_PASSWORD"

# Email (optional - configure after SES setup)
ses_domain      = "yourdomain.com"
mailer_sender   = "AFFiNE <noreply@yourdomain.com>"
```

### 2. Initialize and Apply

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply (creates resources)
terraform apply
```

### 3. Get Connection Info

```bash
# Get outputs
terraform output

# SSH to EC2
ssh -i ~/.ssh/affine-key.pem ec2-user@$(terraform output -raw ec2_public_ip)
```

### 4. Configure Email (SES)

After deployment, you need to:

#### Step 1: Verify your domain in SES

1. Go to AWS Console → SES → Verified Identities
2. Add DNS records shown by `terraform output ses_dns_records`
3. Wait for verification (usually 5-10 minutes)

#### Step 2: Configure SMTP credentials on EC2

```bash
# Get your SES credentials
terraform output ses_smtp_username
terraform output -raw ses_smtp_password

# SSH to EC2 and edit .env
ssh -i affine-key.pem ec2-user@$(terraform output -raw ec2_public_ip)
sudo vi /opt/affine/.env

# Update these lines:
# MAILER_USER=<your_ses_smtp_username>
# MAILER_PASSWORD=<your_ses_smtp_password>

# Restart AFFiNE to apply
cd /opt/affine && sudo docker compose restart affine
```

#### Step 3: Request production access (optional)

By default, SES is in "sandbox mode" and can only send to verified emails.
To send to any email, request production access in AWS Console → SES → Account dashboard.

**Important**: The `.env` file at `/opt/affine/.env` contains email settings. After editing, always recreate the container with:

```bash
cd /opt/affine && sudo docker compose up -d --force-recreate affine
```

(Note: `docker compose restart` does NOT reload .env changes - you must use `--force-recreate`)

## Files

| File                 | Purpose                       |
| -------------------- | ----------------------------- |
| `main.tf`            | Provider configuration        |
| `variables.tf`       | Input variables               |
| `outputs.tf`         | Output values                 |
| `vpc.tf`             | VPC, subnets, security groups |
| `ec2.tf`             | EC2 instance with Docker      |
| `rds.tf`             | RDS PostgreSQL with pgvector  |
| `ses.tf`             | SES email configuration       |
| `user-data.sh`       | EC2 bootstrap script          |
| `docker-compose.yml` | AFFiNE deployment config      |

## Accessing AFFiNE

After deployment:

1. **Web UI**: `http://<EC2_PUBLIC_IP>:3010` (or `https://your-domain.com` if configured)
2. **SSH**: `ssh -i affine-key.pem ec2-user@<EC2_PUBLIC_IP>`

## HTTPS / SSL Setup

To enable HTTPS with a custom domain:

### 1. Add DNS Record

Add an A record pointing to your EC2 Elastic IP:

```
affine.yourdomain.com → <EC2_PUBLIC_IP>
```

### 2. Configure Terraform

Add to `terraform.tfvars`:

```hcl
# Domain for HTTPS
domain_name = "affine.yourdomain.com"
ssl_email   = "admin@yourdomain.com"
```

### 3. Deploy

For new deployments, just run `terraform apply`.

For existing deployments, you need to recreate the EC2 instance:

```bash
# Option 1: Taint and recreate
terraform taint aws_instance.affine
terraform apply

# Option 2: Full redeploy
terraform destroy
terraform apply
```

### How it Works

- **Nginx** is installed as a reverse proxy
- **Let's Encrypt** provides free SSL certificates via Certbot
- **Auto-renewal** is configured via cron (runs daily at noon)
- HTTP traffic is automatically redirected to HTTPS

### Manual SSL Setup (Existing Instance)

If you don't want to recreate the instance:

```bash
ssh -i affine-key.pem ec2-user@<IP>

# Install nginx and certbot
sudo dnf install -y nginx python3-pip
sudo pip3 install certbot certbot-nginx

# Create nginx config
sudo tee /etc/nginx/conf.d/affine.conf << 'EOF'
server {
    listen 80;
    server_name affine.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:3010;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Start nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Get SSL certificate
sudo certbot --nginx -d affine.yourdomain.com
```

## Managing the Deployment

### Helper Scripts (on EC2)

```bash
ssh -i affine-key.pem ec2-user@<IP>
cd /opt/affine

./logs.sh       # View AFFiNE logs
./restart.sh    # Restart AFFiNE
./update.sh     # Update to latest version
./status.sh     # Check status (Docker, nginx, SSL)
./renew-ssl.sh  # Manually renew SSL certificate
```

### Manual Commands

```bash
# View logs
docker logs -f affine_server

# Restart AFFiNE
cd /opt/affine && docker compose restart

# Update to latest version
cd /opt/affine && docker compose pull && docker compose up -d
```

## Configuration Files (on EC2)

| File                             | Purpose                                                      |
| -------------------------------- | ------------------------------------------------------------ |
| `/opt/affine/.env`               | **Email & environment config** - Edit this for SMTP settings |
| `/opt/affine/docker-compose.yml` | Docker services configuration                                |
| `/etc/nginx/conf.d/affine.conf`  | Nginx reverse proxy + SSL config                             |

### Editing Email Configuration

```bash
# SSH to EC2
ssh -i affine-key.pem ec2-user@<IP>

# Edit .env file
sudo vi /opt/affine/.env

# The file contains:
# MAILER_HOST=email-smtp.us-east-1.amazonaws.com
# MAILER_PORT=587
# MAILER_SENDER=AFFiNE <noreply@yourdomain.com>
# MAILER_USER=<your_ses_smtp_username>      # ← Update this
# MAILER_PASSWORD=<your_ses_smtp_password>  # ← Update this

# After editing, recreate container to apply changes
cd /opt/affine && sudo docker compose up -d --force-recreate affine
```

## Backup & Restore

### Backup RDS

RDS automated backups are enabled (7-day retention). For manual snapshots:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier affine-db \
  --db-snapshot-identifier affine-backup-$(date +%Y%m%d)
```

### Backup Uploads (S3)

Uploads are stored on EC2 EBS. To backup:

```bash
# SSH to EC2 and backup to S3
ssh -i ~/.ssh/affine-key.pem ec2-user@<IP> \
  "aws s3 sync /opt/affine/data/storage s3://your-backup-bucket/affine-uploads/"
```

## Destroying Resources

```bash
# Remove all AWS resources
terraform destroy
```

**Warning**: This will delete all data including the database!

## Troubleshooting

### EC2 not starting AFFiNE

```bash
# Check cloud-init logs
ssh -i ~/.ssh/affine-key.pem ec2-user@<IP> "sudo cat /var/log/cloud-init-output.log"

# Check Docker status
ssh -i ~/.ssh/affine-key.pem ec2-user@<IP> "docker ps -a"
```

### Database connection issues

```bash
# Test connection from EC2
ssh -i ~/.ssh/affine-key.pem ec2-user@<IP> \
  "docker run --rm postgres:16 psql postgresql://affine:PASSWORD@RDS_ENDPOINT:5432/affine -c 'SELECT 1;'"
```

### SES not sending emails

1. Check SES is out of sandbox mode
2. Verify sender domain/email is verified
3. Check SES sending limits
