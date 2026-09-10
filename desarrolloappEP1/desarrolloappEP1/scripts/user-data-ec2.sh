#!/bin/bash
# FreshBox SpA - User Data EC2 APP (EP1)
sudo exec > /var/log/user-data.log 2>&1
sudo set -x
sudo yum update -y
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
sudo newgrp docker
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-aarch64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
sudo yum install -y telnet mysql
echo "=== User Data EP1 completado ==="

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
