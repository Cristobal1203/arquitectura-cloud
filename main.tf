provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------
# 1. REDES (VPC y Subredes)
# ------------------------------------------------------
resource "aws_vpc" "automovil_vpc" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "AutomovilTech-VPC", Project = "AutomovilTech" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.automovil_vpc.id
  tags = { Name = "AutomovilTech-IGW" }
}

# Subredes Públicas (Web/App)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.automovil_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1" }
}
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.automovil_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-2" }
}

# Subredes Privadas (Base de Datos)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.automovil_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-Subnet-1" }
}
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.automovil_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "Private-Subnet-2" }
}

# Tabla de rutas pública
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.automovil_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "pub1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "pub2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------------------------------------
# 2. GRUPOS DE SEGURIDAD (Segmentados)
# ------------------------------------------------------
resource "aws_security_group" "alb_sg" {
  name   = "ALB-SG"
  vpc_id = aws_vpc.automovil_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "EC2-App-SG"
  vpc_id = aws_vpc.automovil_vpc.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "RDS-SG"
  vpc_id = aws_vpc.automovil_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
}

# ------------------------------------------------------
# 3. BASE DE DATOS (RDS Multi-AZ y Cifrada)
# ------------------------------------------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "automovil_db" {
  identifier             = "automovil-db"
  engine                 = "mysql"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 50
  storage_type           = "gp3"
  storage_encrypted      = true
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_name                = "automovildb"
  username               = "admin"
  password               = "Automovil2026_!" # Cambiar en prod
  skip_final_snapshot    = true
  backup_retention_period = 7
}

# ------------------------------------------------------
# 4. ROLES IAM (SSM y CloudWatch)[cite: 3]
# ------------------------------------------------------
resource "aws_iam_role" "ec2_role" {
  name = "EC2-SSM-CloudWatch-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "cw_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
resource "aws_iam_role_policy_attachment" "ecr_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2-Profile"
  role = aws_iam_role.ec2_role.name
}

# ------------------------------------------------------
# 5. BALANCEADOR DE CARGA (ALB)[cite: 3]
# ------------------------------------------------------
resource "aws_lb" "app_alb" {
  name               = "Automovil-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "Automovil-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.automovil_vpc.id
  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ------------------------------------------------------
# 6. AUTO SCALING GROUP & LAUNCH TEMPLATE[cite: 3]
# ------------------------------------------------------
resource "aws_launch_template" "app_lt" {
  name          = "Automovil-LT"
  image_id      = "ami-0c101f26f147fa7fd" # Amazon Linux 2023 us-east-1
  instance_type = "t3.micro"
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    security_groups             = [aws_security_group.ec2_sg.id]
    associate_public_ip_address = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # Configuración automatizada con Docker y CloudWatch
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker amazon-cloudwatch-agent
              service docker start
              usermod -a -G docker ec2-user
              
              # Aquí debes inyectar tus variables de entorno para conectarse a RDS
              export DB_HOST=${aws_db_instance.automovil_db.address}
              export DB_USER=${aws_db_instance.automovil_db.username}
              export DB_PASS=${aws_db_instance.automovil_db.password}
              export DB_NAME=${aws_db_instance.automovil_db.db_name}
              
              # Arrancar CloudWatch Agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:AmazonCloudWatch-Config
              EOF
  )
}

resource "aws_autoscaling_group" "app_asg" {
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

# Políticas de Auto Scaling
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "ScaleUpPolicy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

# ------------------------------------------------------
# 7. RECURSOS ADICIONALES (ECR, SNS)[cite: 3]
# ------------------------------------------------------
resource "aws_ecr_repository" "frontend_repo" {
  name = "automovil-frontend"
}
resource "aws_ecr_repository" "backend_repo" {
  name = "automovil-backend"
}
resource "aws_sns_topic" "scaling_alerts" {
  name = "Automovil-Scaling-Alerts"
}