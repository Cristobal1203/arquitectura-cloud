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
      Caso        = "FreshBox-SpA-EP2"
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
  description = "Nombre del ambiente (ep2)."
  type        = string
  default     = "ep2"
}

# ---------- Red (VPC 10.0.0.0/22 - 3 capas x 2 AZ) ----------

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/20"
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
  description = "Subredes privadas de aplicación (Capa App: Nodos EKS)."
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.3.0/24"]
}

variable "data_subnet_cidrs" {
  description = "Subredes privadas de datos (Capa Data: RDS MySQL)."
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24"]
}

# ---------- Cómputo EKS ----------
# Los parámetros de cómputo (instancia, min/max nodos) están en terraform-ep2.tf
# junto con el recurso aws_eks_cluster y aws_eks_node_group.

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
  name        = "${var.project_name}-sg-eks-nodes"
  description = "Nodos EKS - acepta trafico del ALB y comunicacion intra-cluster"
  vpc_id      = aws_vpc.main.id

  # Trafico HTTP desde el ALB (creado por el Ingress Controller)
  ingress {
    description     = "HTTP desde el SG del ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS desde el SG del ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # NodePort range: el ALB Ingress Controller redirige trafico a estos puertos
  ingress {
    description     = "NodePort range desde ALB (Ingress Controller)"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Comunicacion entre nodos del cluster (kubelet, kube-proxy, CNI)
  ingress {
    description = "Trafico interno entre nodos EKS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # API Server -> Nodos (Kubernetes control plane)
  ingress {
    description = "HTTPS desde el API Server de EKS (control plane)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida general: ECR, RDS, API EKS, actualizaciones via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-eks-nodes" }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-sg-rds"
  description = "RDS MySQL Multi-AZ - solo acepta trafico desde nodos EKS (puerto 3306)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL desde nodos EKS (pods de backend)"
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

  tags = { Name = "${var.project_name}-sg-rds" }
}

############################################################
# ALB EP2
# En EP2 el ALB lo crea automaticamente el AWS Load Balancer
# Controller al aplicar el ingress.yaml en Kubernetes.
# NO se crea un ALB manual aqui para evitar conflictos.
# El SG del ALB (aws_security_group.alb) si se crea arriba
# porque el Ingress Controller necesita un SG para el ALB.
############################################################
# (ALB creado por Kubernetes Ingress Controller — ver k8s/ingress.yaml)

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
# IAM - referencia al LabRole del Learner Lab
############################################################
# El Learner Lab proporciona LabRole con permisos amplios.
# EKS usa este rol tanto para el cluster como para los nodos.
# Ver data sources en terraform-ep2.tf (data.aws_iam_role.eks_cluster_role)
# No se necesita aws_iam_instance_profile en EP2 (EKS gestiona esto).

############################################################
# RDS MySQL Multi-AZ — Capa Data (EP2)
#
# EP2 pide: db.t4g.small MySQL Multi-AZ con snapshots automaticos.
# En el Learner Lab, db.t3.micro es la opcion mas compatible.
# multi_az = true: AWS crea una instancia standby en otra AZ y
# hace failover automatico si la primaria falla (RTO < 2 min).
# storage_encrypted = true: cifrado AES-256 en reposo (criterio IE3.2.2).
# backup_retention_period: snapshots automaticos por 7 dias.
############################################################

resource "aws_db_subnet_group" "mysql" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.data[*].id

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier = "${var.project_name}-mysql"

  engine         = "mysql"
  engine_version = var.db_engine_version  # 8.0

  # db.t3.micro: 2 vCPU, 1 GB RAM — compatible con Learner Lab
  # La pauta pide db.t4g.small; si esta disponible, cambiar aqui
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage  # 20 GB
  storage_type      = "gp2"
  storage_encrypted = true  # Cifrado EBS RDS (IE3.2.2)

  db_name  = var.db_name      # freshbox
  username = var.db_username  # alumno
  password = var.db_password  # via tfvars / TF_VAR_db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # Multi-AZ: crea standby sincronico en otra AZ (IE3.2.2 Alta Disponibilidad)
  multi_az            = true
  publicly_accessible = false

  # Snapshots automaticos: recuperacion ante fallos (IE3.2.2 Respaldo)
  backup_retention_period = var.db_backup_retention_days  # 7 dias
  backup_window           = "05:00-06:00"
  maintenance_window      = "sun:06:30-sun:07:30"

  # Apagar monitoreo mejorado: no disponible en Learner Lab
  monitoring_interval = 0

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = { Name = "${var.project_name}-mysql-multiaz" }
}

############################################################
# COMPUTO EP2: EKS CLUSTER + NODE GROUP
# Los recursos aws_eks_cluster y aws_eks_node_group estan
# definidos en terraform-ep2.tf (mismo directorio).
# Terraform unifica automaticamente todos los .tf del directorio.
############################################################

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
# OUTPUTS EP2
############################################################

output "vpc_id" {
  description = "ID de la VPC Multi-AZ"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Subredes publicas (ALB, NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Subredes privadas de app (Nodos EKS)"
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Subredes privadas de datos (RDS MySQL)"
  value       = aws_subnet.data[*].id
}

output "nat_gateway_ips" {
  description = "IPs publicas de los NAT Gateways (uno por AZ)"
  value       = aws_eip.nat[*].public_ip
}

output "sg_alb_id" {
  description = "Security Group del ALB (referenciado por Ingress Controller)"
  value       = aws_security_group.alb.id
}

output "sg_eks_nodes_id" {
  description = "Security Group de los nodos EKS"
  value       = aws_security_group.app.id
}

output "sg_rds_id" {
  description = "Security Group de RDS MySQL"
  value       = aws_security_group.db.id
}

output "ecr_repository_urls" {
  description = "URLs de los 5 repositorios ECR (usar para docker push y manifiestos K8s)"
  value       = local.ecr_repo_urls
}

output "ecr_registry" {
  description = "Registry ECR base (ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com)"
  value       = local.ecr_registry
}

output "rds_endpoint" {
  description = "Endpoint completo de RDS (host:puerto) — usar en k8s/configmap.yaml"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_address" {
  description = "Host de RDS — usar como DB_HOST en ConfigMap de Kubernetes"
  value       = aws_db_instance.mysql.address
}

output "rds_multi_az" {
  description = "Confirma que RDS esta en Multi-AZ (debe ser true)"
  value       = aws_db_instance.mysql.multi_az
}

# EKS outputs definidos en terraform-ep2.tf
# eks_cluster_name, eks_cluster_endpoint, eks_kubeconfig_command
