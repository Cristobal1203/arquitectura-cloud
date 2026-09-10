provider "aws" {
  region = "us-east-1"
}

# 1. VPC y Gateways
resource "aws_vpc" "freshbox_vpc" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "VPC-FreshBox" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.freshbox_vpc.id
  tags = { Name = "IGW-FreshBox" }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# 2. Subred Pública (AZ 1a) y NAT Gateway
resource "aws_subnet" "public_az1a" {
  vpc_id                  = aws_vpc.freshbox_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-AZ1a" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_az1a.id
  tags = { Name = "NAT-FreshBox" }
}

# 3. Subredes Privadas (Ejemplo Capa App)
resource "aws_subnet" "private_app_az1a" {
  vpc_id            = aws_vpc.freshbox_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-App-AZ1a" }
}

# 4. Security Groups Encadenados
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  vpc_id      = aws_vpc.freshbox_vpc.id
  description = "Permitir HTTP/HTTPS desde Internet"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  vpc_id      = aws_vpc.freshbox_vpc.id
  description = "Permitir trafico solo desde el ALB"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  vpc_id      = aws_vpc.freshbox_vpc.id
  description = "Permitir MySQL solo desde la capa App"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
}

# 5. Elastic Container Registry (ECR)
resource "aws_ecr_repository" "freshbox_repo" {
  name                 = "freshbox-microservices"
  image_tag_mutability = "MUTABLE"
}