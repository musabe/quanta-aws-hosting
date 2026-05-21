#!/bin/bash
# modules/ec2-nginx/templates/user_data.sh
# Bootstraps EC2 instance with Nginx and pulls website content from S3.
# Runs once at instance creation. For redeployment, CI/CD uses SSM Run Command.

set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting bootstrap: $(date) ==="

# ─────────────────────────────────────────────
# System updates
# ─────────────────────────────────────────────
dnf update -y
dnf install -y nginx amazon-cloudwatch-agent

# ─────────────────────────────────────────────
# Nginx configuration
# ─────────────────────────────────────────────
cat > /etc/nginx/conf.d/${project_name}.conf << 'NGINX_EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    # Health check endpoint for ALB
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Serve static files; fallback to index.html for SPA routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    gzip_min_length 256;
}
NGINX_EOF

# Remove default Nginx config
rm -f /etc/nginx/conf.d/default.conf

# Create web root
mkdir -p /var/www/html

# ─────────────────────────────────────────────
# Pull website content from S3
# ─────────────────────────────────────────────
aws s3 sync s3://${content_s3_bucket}/solution-b/ /var/www/html/ \
  --region ${aws_region} \
  --delete

# ─────────────────────────────────────────────
# Set permissions
# ─────────────────────────────────────────────
chown -R nginx:nginx /var/www/html
chmod -R 755 /var/www/html

# ─────────────────────────────────────────────
# Enable and start Nginx
# ─────────────────────────────────────────────
systemctl enable nginx
systemctl start nginx

# ─────────────────────────────────────────────
# CloudWatch Agent configuration
# ─────────────────────────────────────────────
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}/nginx-access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}/nginx-error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CW_EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "=== Bootstrap complete: $(date) ==="
