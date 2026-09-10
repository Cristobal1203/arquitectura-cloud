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

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_az1a.id # El NAT va en la subred pública
  tags = { Name = "NAT-FreshBox" }
}

# 2. Subredes Públicas (Capa 1)
resource "aws_subnet" "public_az1a" {
  vpc_id                  = aws_vpc.freshbox_vpc.id
  cidr_block              = "10.0.0.0/26"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-AZ1a" }
}

resource "aws_subnet" "public_az1b" {
  vpc_id                  = aws_vpc.freshbox_vpc.id
  cidr_block              = "10.0.0.64/26"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-AZ1b" }
}

# 3. Subredes Privadas App (Capa 2)
resource "aws_subnet" "private_app_az1a" {
  vpc_id            = aws_vpc.freshbox_vpc.id
  cidr_block        = "10.0.1.0/26"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-App-AZ1a" }
}

resource "aws_subnet" "private_app_az1b" {
  vpc_id            = aws_vpc.freshbox_vpc.id
  cidr_block        = "10.0.1.64/26"
  availability_zone = "us-east-1b"
  tags = { Name = "Private-App-AZ1b" }
}

# 4. Subredes Privadas Data (Capa 3)
resource "aws_subnet" "private_data_az1a" {
  vpc_id            = aws_vpc.freshbox_vpc.id
  cidr_block        = "10.0.2.0/26"
  availability_zone = "us-east-1a"
  tags = { Name = "Private-Data-AZ1a" }
}

resource "aws_subnet" "private_data_az1b" {
  vpc_id            = aws_vpc.freshbox_vpc.id
  cidr_block        = "10.0.2.64/26"
  availability_zone = "us-east-1b"
  tags = { Name = "Private-Data-AZ1b" }
}

# 5. Tablas de Enrutamiento (Route Tables)
# Tabla Pública: Apunta a Internet a través del IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.freshbox_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Public-RouteTable" }
}

# Tabla Privada: Apunta a Internet a través del NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.freshbox_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "Private-RouteTable" }
}

# 6. Asociaciones de Tablas de Enrutamiento
# Asociamos las subredes públicas a la tabla pública
resource "aws_route_table_association" "public_az1a_assoc" {
  subnet_id      = aws_subnet.public_az1a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_az1b_assoc" {
  subnet_id      = aws_subnet.public_az1b.id
  route_table_id = aws_route_table.public_rt.id
}

# Asociamos TODAS las subredes privadas (App y Data) a la tabla privada
resource "aws_route_table_association" "private_app_az1a_assoc" {
  subnet_id      = aws_subnet.private_app_az1a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_app_az1b_assoc" {
  subnet_id      = aws_subnet.private_app_az1b.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_data_az1a_assoc" {
  subnet_id      = aws_subnet.private_data_az1a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_data_az1b_assoc" {
  subnet_id      = aws_subnet.private_data_az1b.id
  route_table_id = aws_route_table.private_rt.id
}