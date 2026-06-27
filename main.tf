provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------
# 1. NETWORKING (VPC, Subnets, IGW, NAT, Route Tables)
# ------------------------------------------------------
resource "aws_vpc" "technova_vpc" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "VPC-TechNova", Project = "TechNova", Environment = "Production", CostCenter = "IT-Ops" }
}

resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.technova_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a", Project = "TechNova", Environment = "Production" }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.technova_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1b", Project = "TechNova", Environment = "Production" }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.technova_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-Subnet-1a", Project = "TechNova", Environment = "Production" }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.technova_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "Private-Subnet-1b", Project = "TechNova", Environment = "Production" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.technova_vpc.id
  tags = { Name = "IGW-TechNova", Project = "TechNova" }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = { Name = "EIP-NAT-TechNova", Project = "TechNova" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1a.id
  tags = { Name = "NAT-TechNova", Project = "TechNova" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.technova_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Public-RT", Project = "TechNova" }
}

resource "aws_route_table_association" "pub_1a_assoc" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "pub_1b_assoc" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.technova_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "Private-RT", Project = "TechNova" }
}

resource "aws_route_table_association" "priv_1a_assoc" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "priv_1b_assoc" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_rt.id
}

# ------------------------------------------------------
# 2. SECURITY GROUPS
# ------------------------------------------------------
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Permitir trafico HTTP/HTTPS al ALB"
  vpc_id      = aws_vpc.technova_vpc.id

  ingress { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "SG-ALB-TechNova", Project = "TechNova" }
}

resource "aws_security_group" "ec2_sg" {
  name        = "EC2-App-SG"
  description = "Permitir trafico desde ALB a EC2"
  vpc_id      = aws_vpc.technova_vpc.id

  ingress { from_port = 80, to_port = 80, protocol = "tcp", security_groups = [aws_security_group.alb_sg.id] }
  ingress { from_port = 3001, to_port = 3001, protocol = "tcp", security_groups = [aws_security_group.alb_sg.id] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "SG-EC2-TechNova", Project = "TechNova" }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDS-SG"
  description = "Permitir trafico MySQL desde EC2"
  vpc_id      = aws_vpc.technova_vpc.id

  ingress { from_port = 3306, to_port = 3306, protocol = "tcp", security_groups = [aws_security_group.ec2_sg.id] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "SG-RDS-TechNova", Project = "TechNova" }
}

# ------------------------------------------------------
# 3. COMPUTE (ALB, Launch Template, ASG)
# ------------------------------------------------------
resource "aws_lb" "app_alb" {
  name               = "TechNova-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
  tags = { Name = "ALB-TechNova", Project = "TechNova", Environment = "Production" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "TechNova-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.technova_vpc.id
  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Busca la AMI de Ubuntu 24.04 (o usa la tuya si la tienes en AWS Academy)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter { name = "name", values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] }
}

resource "aws_launch_template" "app_lt" {
  name          = "TechNova-Launch-Template"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  
  iam_instance_profile {
    name = "LabInstanceProfile" # Perfil obligatorio en Learner Lab
  }

  network_interfaces {
    security_groups = [aws_security_group.ec2_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 50
      volume_type = "gp3"
    }
  }

  # User data basico para instalar Docker y arrancar contenedores si los tienes
  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io docker-compose
              systemctl enable docker
              systemctl start docker
              EOF
  )
  tags = { Name = "LT-TechNova", Project = "TechNova" }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "TechNova-ASG"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "TechNova-ASG-Instance"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "TechNova"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }
}

# ------------------------------------------------------
# 4. DATABASE (RDS Multi-AZ)
# ------------------------------------------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "technova-db-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
  tags = { Name = "RDS-Subnet-Group", Project = "TechNova" }
}

resource "aws_db_instance" "rds_db" {
  identifier             = "rds-technova2"
  allocated_storage      = 50
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.medium"
  username               = "admin"
  password               = "Technova2026!" # Cambiar en producción
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az               = true
  skip_final_snapshot    = true
  tags = { Name = "RDS-TechNova", Project = "TechNova", Environment = "Production" }
}