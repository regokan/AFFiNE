#!/bin/bash
set -e

# =============================================================================
# AFFiNE EC2 User Data Script
# This script runs on first boot to set up AFFiNE
# =============================================================================

exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting AFFiNE setup at $(date)"

# -----------------------------------------------------------------------------
# Install Docker
# -----------------------------------------------------------------------------

echo "Installing Docker..."
dnf update -y
dnf install -y docker

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Also install as Docker plugin
mkdir -p /usr/local/lib/docker/cli-plugins
ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# -----------------------------------------------------------------------------
# Install PostgreSQL client & utilities
# -----------------------------------------------------------------------------

echo "Installing PostgreSQL client and utilities..."
dnf install -y postgresql16 jq

# -----------------------------------------------------------------------------
# Wait for RDS to be ready
# -----------------------------------------------------------------------------

echo "Waiting for RDS to be ready..."
max_attempts=30
attempt=0
until PGPASSWORD='${db_password}' psql -h '${db_host}' -U '${db_username}' -d '${db_name}' -c '\q' 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: RDS not ready after $max_attempts attempts"
        exit 1
    fi
    echo "Waiting for RDS... (attempt $attempt/$max_attempts)"
    sleep 10
done
echo "RDS is ready!"

# -----------------------------------------------------------------------------
# Enable pgvector extension
# -----------------------------------------------------------------------------

echo "Enabling pgvector extension..."
PGPASSWORD='${db_password}' psql -h '${db_host}' -U '${db_username}' -d '${db_name}' -c 'CREATE EXTENSION IF NOT EXISTS vector;'

# -----------------------------------------------------------------------------
# Create AFFiNE directory
# -----------------------------------------------------------------------------

echo "Creating AFFiNE directory..."
mkdir -p /opt/affine/data/storage
mkdir -p /opt/affine/data/config
chown -R 1000:1000 /opt/affine

# -----------------------------------------------------------------------------
# Create AFFiNE config file (for copilot/AI features)
# -----------------------------------------------------------------------------

OPENAI_API_KEY="${openai_api_key}"

if [ -n "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "" ]; then
    echo "Configuring AFFiNE Copilot with OpenAI..."
    cat > /opt/affine/data/config/config.json << CONFIG_EOF
{
  "copilot": {
    "enabled": true,
    "scenarios": {
      "override_enabled": true,
      "scenarios": {
        "audio_transcribing": "gpt-4o-audio-preview",
        "chat": "gpt-5.2",
        "embedding": "text-embedding-3-large",
        "image": "dall-e-3",
        "rerank": "gpt-5-mini",
        "coding": "gpt-5.2",
        "complex_text_generation": "gpt-5.2",
        "quick_decision_making": "gpt-5-mini",
        "quick_text_generation": "gpt-5-mini",
        "polish_and_summarize": "gpt-5-mini"
      }
    },
    "providers": {
      "openai": {
        "apiKey": "$OPENAI_API_KEY",
        "baseURL": "https://api.openai.com/v1"
      }
    }
  }
}
CONFIG_EOF
    chown 1000:1000 /opt/affine/data/config/config.json
    echo "Copilot configured with OpenAI provider"
else
    echo "No OpenAI API key provided, copilot will be disabled"
    echo '{}' > /opt/affine/data/config/config.json
    chown 1000:1000 /opt/affine/data/config/config.json
fi

# -----------------------------------------------------------------------------
# Create Docker Compose file
# -----------------------------------------------------------------------------

echo "Creating Docker Compose configuration..."
cat > /opt/affine/docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  # Migration service - runs database migrations before starting server
  affine_migration:
    image: ghcr.io/toeverything/affine:${affine_revision}
    container_name: affine_migration
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://${db_username}:${db_password}@${db_host}:${db_port}/${db_name}
    command: ['sh', '-c', 'node ./scripts/self-host-predeploy.js']
    depends_on:
      redis:
        condition: service_healthy

  # Main AFFiNE server
  affine:
    image: ghcr.io/toeverything/affine:${affine_revision}
    container_name: affine_server
    restart: unless-stopped
    ports:
      - "3010:3010"
      - "5555:5555"
    env_file:
      - .env
    environment:
      - NODE_ENV=production
      - AFFINE_SERVER_HOST=0.0.0.0
      - AFFINE_SERVER_PORT=3010
      - AFFINE_SERVER_EXTERNAL_URL=${domain_name != "" ? "https://${domain_name}" : ""}
      - DATABASE_URL=postgresql://${db_username}:${db_password}@${db_host}:${db_port}/${db_name}
      - REDIS_SERVER_HOST=redis
      - REDIS_SERVER_PORT=6379
    volumes:
      - ./data/storage:/root/.affine/storage
      - ./data/config:/root/.affine/config
    depends_on:
      redis:
        condition: service_healthy
      affine_migration:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3010/info"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  redis:
    image: redis:7-alpine
    container_name: affine_redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  redis_data:
COMPOSE_EOF

# -----------------------------------------------------------------------------
# Create .env file for email configuration
# -----------------------------------------------------------------------------

cat > /opt/affine/.env << ENV_EOF
# =============================================================================
# AFFiNE Environment Configuration
# =============================================================================
# This file is loaded by docker-compose for the AFFiNE container.
# After editing, recreate container: docker compose up -d --force-recreate affine
# =============================================================================

# -----------------------------------------------------------------------------
# Email Configuration (Required for verification emails)
# -----------------------------------------------------------------------------
# Get these values from: terraform output ses_smtp_username
#                        terraform output -raw ses_smtp_password

MAILER_HOST=email-smtp.${aws_region}.amazonaws.com
MAILER_PORT=587
MAILER_SENDER=${mailer_sender}
MAILER_USER=CHANGE_ME_SES_SMTP_USERNAME
MAILER_PASSWORD=CHANGE_ME_SES_SMTP_PASSWORD

# Set to true for production (TLS)
MAILER_SECURE=false
ENV_EOF

# -----------------------------------------------------------------------------
# Start AFFiNE
# -----------------------------------------------------------------------------

echo "Starting AFFiNE..."
cd /opt/affine
docker compose up -d

# -----------------------------------------------------------------------------
# Wait for AFFiNE to be healthy
# -----------------------------------------------------------------------------

echo "Waiting for AFFiNE to start..."
max_attempts=30
attempt=0
until curl -sf http://localhost:3010/info > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "WARNING: AFFiNE not responding after $max_attempts attempts"
        echo "Check logs with: docker logs affine_server"
        break
    fi
    echo "Waiting for AFFiNE... (attempt $attempt/$max_attempts)"
    sleep 10
done

if curl -sf http://localhost:3010/info > /dev/null 2>&1; then
    echo "AFFiNE is running!"
fi

# -----------------------------------------------------------------------------
# Setup Nginx & SSL (if domain is configured)
# -----------------------------------------------------------------------------

DOMAIN_NAME="${domain_name}"
SSL_EMAIL="${ssl_email}"

if [ -n "$DOMAIN_NAME" ] && [ "$DOMAIN_NAME" != "" ]; then
    echo "Setting up Nginx and SSL for $DOMAIN_NAME..."
    
    # Install nginx
    echo "Installing Nginx..."
    dnf install -y nginx
    
    # Install certbot via pip (more reliable on Amazon Linux 2023)
    echo "Installing Certbot..."
    dnf install -y python3-pip augeas-libs
    pip3 install certbot certbot-nginx
    
    # Create nginx config for AFFiNE (HTTP first, for certbot validation)
    echo "Configuring Nginx..."
    cat > /etc/nginx/conf.d/affine.conf << 'NGINX_EOF'
server {
    listen 80;
    listen [::]:80;
    server_name ${domain_name};

    # For Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://127.0.0.1:3010;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        
        # WebSocket support
        proxy_buffering off;
        proxy_cache off;
    }
}
NGINX_EOF

    # Create certbot webroot directory
    mkdir -p /var/www/certbot
    
    # Remove default nginx config if exists
    rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
    
    # Start nginx
    systemctl enable nginx
    systemctl start nginx
    
    # Wait a moment for nginx to start
    sleep 5
    
    # Get SSL certificate
    echo "Obtaining SSL certificate..."
    if [ -n "$SSL_EMAIL" ] && [ "$SSL_EMAIL" != "" ]; then
        /usr/local/bin/certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect
    else
        /usr/local/bin/certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect
    fi
    
    # Setup auto-renewal via systemd timer (more reliable than cron on Amazon Linux 2023)
    echo "Setting up SSL auto-renewal..."
    cat > /etc/systemd/system/certbot-renewal.service << 'CERTBOT_SERVICE'
[Unit]
Description=Certbot Renewal

[Service]
Type=oneshot
ExecStart=/usr/local/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
CERTBOT_SERVICE

    cat > /etc/systemd/system/certbot-renewal.timer << 'CERTBOT_TIMER'
[Unit]
Description=Run certbot renewal twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
CERTBOT_TIMER

    systemctl daemon-reload
    systemctl enable certbot-renewal.timer
    systemctl start certbot-renewal.timer
    
    # Restart nginx to apply SSL config
    systemctl restart nginx
    
    echo "SSL setup complete! AFFiNE is now available at https://$DOMAIN_NAME"
else
    echo "No domain configured, skipping SSL setup."
    echo "AFFiNE is available at http://<PUBLIC_IP>:3010"
fi

# -----------------------------------------------------------------------------
# Create helper scripts
# -----------------------------------------------------------------------------

# Logs script
cat > /opt/affine/logs.sh << 'SCRIPT_EOF'
#!/bin/bash
docker logs -f affine_server
SCRIPT_EOF
chmod +x /opt/affine/logs.sh

# Restart script
cat > /opt/affine/restart.sh << 'SCRIPT_EOF'
#!/bin/bash
cd /opt/affine
docker compose restart
SCRIPT_EOF
chmod +x /opt/affine/restart.sh

# Update script
cat > /opt/affine/update.sh << 'SCRIPT_EOF'
#!/bin/bash
cd /opt/affine
docker compose pull
docker compose up -d
SCRIPT_EOF
chmod +x /opt/affine/update.sh

# Status script
cat > /opt/affine/status.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "=== Docker Containers ==="
docker ps -a
echo ""
echo "=== AFFiNE Health ==="
curl -s http://localhost:3010/info | jq . 2>/dev/null || echo "AFFiNE not responding"
echo ""
echo "=== Nginx Status ==="
systemctl status nginx --no-pager 2>/dev/null || echo "Nginx not installed"
echo ""
echo "=== SSL Certificate ==="
certbot certificates 2>/dev/null || echo "No SSL certificates"
echo ""
echo "=== Disk Usage ==="
df -h /opt/affine
SCRIPT_EOF
chmod +x /opt/affine/status.sh

# SSL renewal script
cat > /opt/affine/renew-ssl.sh << 'SCRIPT_EOF'
#!/bin/bash
certbot renew --quiet
systemctl reload nginx
SCRIPT_EOF
chmod +x /opt/affine/renew-ssl.sh

echo ""
echo "============================================================"
echo "AFFiNE setup complete!"
echo "============================================================"
echo ""
if [ -n "$DOMAIN_NAME" ] && [ "$DOMAIN_NAME" != "" ]; then
    echo "Access AFFiNE at: https://$DOMAIN_NAME"
else
    echo "Access AFFiNE at: http://<PUBLIC_IP>:3010"
fi
echo ""
echo "Helper scripts in /opt/affine/:"
echo "  ./logs.sh      - View AFFiNE logs"
echo "  ./restart.sh   - Restart AFFiNE"
echo "  ./update.sh    - Update to latest version"
echo "  ./status.sh    - Check status"
echo "  ./renew-ssl.sh - Renew SSL certificate"
echo ""
echo "Setup completed at $(date)"
