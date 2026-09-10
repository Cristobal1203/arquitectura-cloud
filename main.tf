terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Caso        = "FreshBox-SpA-EP1"
    }
  }
}

############################################################
# VARIABLES
############################################################

# ---------- General ----------

variable "aws_region" {
  description = "Región AWS. AWS Academy Learner Lab solo habilita us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo usado en el nombre de todos los recursos."
  type        = string
  default     = "freshbox"
}

variable "environment" {
  description = "Nombre del ambiente (ep1, dev, prod, etc.)."
  type        = string
  default     = "ep1"
}

# ---------- Red (VPC 10.0.0.0/22 - 3 capas x 2 AZ) ----------

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/22"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Subredes públicas (Capa Web: ALB)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Subredes privadas de aplicación (Capa App: EC2 + Docker)."
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.3.0/24"]
}

variable "data_subnet_cidrs" {
  description = "Subredes privadas de datos (Capa Data: RDS MySQL)."
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24"]
}

# ---------- Cómputo / Auto Scaling Group ----------

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

# AWS Academy Learner Lab NO permite crear roles/policies IAM propios.
# Se reutiliza el Instance Profile ya entregado por el laboratorio.
# Verifica el nombre real con:
#   aws iam list-instance-profiles --query "InstanceProfiles[].InstanceProfileName"
variable "lab_instance_profile_name" {
  type    = string
  default = "LabInstanceProfile"
}

# ---------- Contenedores / ECR ----------

variable "ecr_repository_names" {
  description = "1 frontend + 4 microservicios backend."
  type        = list(string)
  default = [
    "frontend",
    "get-products",
    "create-product",
    "update-product",
    "delete-product",
  ]
}

variable "container_image_tag" {
  type    = string
  default = "latest"
}

# ---------- Base de datos (RDS MySQL Multi-AZ) ----------

variable "db_name" {
  type    = string
  default = "freshbox"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  description = "Password de RDS. Pasar vía terraform.tfvars (no versionado) o TF_VAR_db_password. NO hardcodear."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "En AWS Academy suele estar limitado a familias burstable pequeñas."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  type    = string
  default = "8.0"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

# ---------- AWS Backup ----------

# En AWS Academy Learner Lab, "AWSBackupDefaultServiceRole" NO existe:
# ese rol lo crea automaticamente la consola de AWS Backup la primera vez
# que se usa desde ahi, y esa operacion requiere iam:CreateRole, permiso
# que el laboratorio no entrega. Por eso el default aqui es false; RDS ya
# hace respaldo automatico nativo via backup_retention_period (abajo),
# lo que igual cumple el criterio de "Respaldo" de la pauta.
variable "enable_aws_backup" {
  description = "Dejar en false en AWS Academy Learner Lab (el rol de servicio de Backup no esta disponible). Poner en true solo en una cuenta AWS propia donde el rol ya exista o puedas crearlo."
  type        = bool
  default     = false
}

variable "backup_service_role_name" {
  type    = string
  default = "AWSBackupDefaultServiceRole"
}

############################################################
# RED: VPC, subredes, IGW, NAT Gateways, tablas de ruteo
############################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# Capa 1 Web (pública): ALB
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# Capa 2 App (privada): EC2 + Docker / ASG
resource "aws_subnet" "app" {
  count             = length(var.app_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-app-${var.availability_zones[count.index]}"
    Tier = "app"
  }
}

# Capa 3 Data (privada): RDS MySQL
resource "aws_subnet" "data" {
  count             = length(var.data_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-data-${var.availability_zones[count.index]}"
    Tier = "data"
  }
}

# NAT Gateway por AZ (alta disponibilidad real)
resource "aws_eip" "nat" {
  count      = length(var.public_subnet_cidrs)
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "${var.project_name}-nat-eip-${var.availability_zones[count.index]}" }
}

resource "aws_nat_gateway" "nat" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.igw]

  tags = { Name = "${var.project_name}-nat-${var.availability_zones[count.index]}" }
}

# Ruteo público -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Ruteo Capa App -> NAT Gateway de su propia AZ
resource "aws_route_table" "app" {
  count  = length(var.app_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = { Name = "${var.project_name}-rt-app-${var.availability_zones[count.index]}" }
}

resource "aws_route_table_association" "app" {
  count          = length(aws_subnet.app)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# Ruteo Capa Data -> aislada, sin salida a Internet
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-rt-data" }
}

resource "aws_route_table_association" "data" {
  count          = length(aws_subnet.data)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

############################################################
# SECURITY GROUPS (segmentados por capa)
############################################################

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Trafico HTTP/HTTPS publico hacia el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS desde Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg-app"
  description = "EC2 capa aplicacion - solo acepta trafico del ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP desde el ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS desde el ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Salida general (ECR, actualizaciones OS, RDS) via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-app" }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-sg-db"
  description = "RDS MySQL - solo acepta trafico de la capa App"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL desde EC2 App"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-db" }
}

############################################################
# ALB (un solo Load Balancer, multi-AZ)
############################################################

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg-app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project_name}-tg-app" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

############################################################
# ECR (5 repositorios: frontend + 4 microservicios)
############################################################

data "aws_caller_identity" "current" {}

locals {
  ecr_registry  = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  ecr_repo_urls = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

resource "aws_ecr_repository" "services" {
  for_each             = toset(var.ecr_repository_names)
  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.project_name}-ecr-${each.value}" }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener solo las ultimas 5 imagenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = { type = "expire" }
      }
    ]
  })
}

############################################################
# IAM - referencia al Instance Profile existente (Academy Lab)
############################################################

# AWS Academy Learner Lab no permite iam:CreateRole. Se reutiliza el
# LabInstanceProfile/LabRole que el laboratorio ya entrega.
data "aws_iam_instance_profile" "lab" {
  name = var.lab_instance_profile_name
}

############################################################
# RDS MySQL Multi-AZ (según diagrama TO-BE del estudiante)
############################################################

# NOTA: la pauta oficial describe la Capa Data como "EC2 + MySQL"
# autogestionado; aquí se implementa RDS Multi-AZ replicando el
# diagrama TO-BE (2 nodos con "sincronización" entre AZ1a/AZ1b).
# Documentar esta decisión en el informe (1.3 y 1.7) como mejora de
# Confiabilidad / Excelencia Operacional del Well-Architected Framework.

resource "aws_db_subnet_group" "mysql" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.data[*].id

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier = "${var.project_name}-mysql"

  engine         = "mysql"
  engine_version = var.db_engine_version

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.db.id]

  multi_az            = true
  publicly_accessible = false

  backup_retention_period = var.db_backup_retention_days
  backup_window            = "05:00-06:00"
  maintenance_window       = "sun:06:30-sun:07:30"

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately    = true

  tags = { Name = "${var.project_name}-mysql" }
}

############################################################
# AUTO SCALING GROUP (EC2 t4g.small + Docker)
############################################################

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type            = "gp3"
      encrypted              = true
      delete_on_termination  = true
    }
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 obligatorio
    http_endpoint = "enabled"
  }

  # Bootstrap: instala Docker, autentica con ECR y levanta los 5
  # contenedores (1 frontend + 4 backend Node.js) via docker compose.
  user_data = base64encode(<<EOT
#!/bin/bash
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

aws ecr get-login-password --region ${var.aws_region} | \
  docker login --username AWS --password-stdin ${local.ecr_registry}

mkdir -p /opt/freshbox
cat <<'COMPOSE' > /opt/freshbox/docker-compose.yml
version: "3.9"
services:
  frontend:
    image: ${local.ecr_repo_urls["frontend"]}:${var.container_image_tag}
    restart: always
    ports:
      - "80:80"
    depends_on:
      - get-products
      - create-product
      - update-product
      - delete-product

  get-products:
    image: ${local.ecr_repo_urls["get-products"]}:${var.container_image_tag}
    restart: always
    environment:
      DB_HOST: ${aws_db_instance.mysql.address}
      DB_PORT: "${aws_db_instance.mysql.port}"
      DB_NAME: ${var.db_name}
      DB_USER: ${var.db_username}
      DB_PASSWORD: ${var.db_password}

  create-product:
    image: ${local.ecr_repo_urls["create-product"]}:${var.container_image_tag}
    restart: always
    environment:
      DB_HOST: ${aws_db_instance.mysql.address}
      DB_PORT: "${aws_db_instance.mysql.port}"
      DB_NAME: ${var.db_name}
      DB_USER: ${var.db_username}
      DB_PASSWORD: ${var.db_password}

  update-product:
    image: ${local.ecr_repo_urls["update-product"]}:${var.container_image_tag}
    restart: always
    environment:
      DB_HOST: ${aws_db_instance.mysql.address}
      DB_PORT: "${aws_db_instance.mysql.port}"
      DB_NAME: ${var.db_name}
      DB_USER: ${var.db_username}
      DB_PASSWORD: ${var.db_password}

  delete-product:
    image: ${local.ecr_repo_urls["delete-product"]}:${var.container_image_tag}
    restart: always
    environment:
      DB_HOST: ${aws_db_instance.mysql.address}
      DB_PORT: "${aws_db_instance.mysql.port}"
      DB_NAME: ${var.db_name}
      DB_USER: ${var.db_username}
      DB_PASSWORD: ${var.db_password}
COMPOSE

cd /opt/freshbox
docker compose pull
docker compose up -d
EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-asg-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

############################################################
# AWS BACKUP (respaldo de RDS)
############################################################

# Desactivado por defecto (enable_aws_backup = false) porque
# AWSBackupDefaultServiceRole no existe en AWS Academy Learner Lab.
# RDS ya hace backups automaticos nativos via backup_retention_period,
# lo que igual cumple el criterio de "Respaldo" de la pauta.

resource "aws_backup_vault" "main" {
  count = var.enable_aws_backup ? 1 : 0
  name  = "${var.project_name}-backup-vault"
}

resource "aws_backup_plan" "main" {
  count = var.enable_aws_backup ? 1 : 0
  name  = "${var.project_name}-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = "cron(0 7 * * ? *)"

    lifecycle {
      delete_after = var.db_backup_retention_days
    }
  }
}

data "aws_iam_role" "backup" {
  count = var.enable_aws_backup ? 1 : 0
  name  = var.backup_service_role_name
}

resource "aws_backup_selection" "rds" {
  count        = var.enable_aws_backup ? 1 : 0
  name         = "${var.project_name}-backup-rds"
  plan_id      = aws_backup_plan.main[0].id
  iam_role_arn = data.aws_iam_role.backup[0].arn

  resources = [aws_db_instance.mysql.arn]
}

############################################################
# OUTPUTS
############################################################

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "nat_gateway_ips" {
  description = "IP publica de cada NAT Gateway (uno por AZ)"
  value       = aws_eip.nat[*].public_ip
}

output "alb_url" {
  description = "URL de la aplicacion (frontend via ALB)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_urls" {
  description = "URLs de los 5 repositorios ECR para hacer docker push"
  value       = local.ecr_repo_urls
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "rds_address" {
  value = aws_db_instance.mysql.address
}
