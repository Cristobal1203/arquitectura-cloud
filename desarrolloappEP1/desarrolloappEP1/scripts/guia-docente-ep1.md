# Guia Docente — Implementacion EP1 (FreshBox SpA)

## Referencia para el docente — NO entregar al estudiante

| Campo | Valor |
|-------|-------|
| Caso | FreshBox SpA - Catalogo Online Productos Organicos |
| Arquitectura | 3 capas: EC2+Docker + MySQL + ALB Multi-AZ |
| Region | us-east-1 |
| Instancias | t4g.small (ARM Graviton) |

---

## Pasos de implementacion esperados

### 1. VPC Multi-AZ
- VPC 10.0.0.0/22
- 2 subredes publicas (AZ1a, AZ1b) para ALB
- 2 subredes privadas APP (AZ1a, AZ1b) para EC2 APP
- 2 subredes privadas DATA (AZ1a, AZ1b) para EC2 MySQL
- Internet Gateway + NAT Gateway (AZ1a)

### 2. Security Groups
- SG-ALB: TCP 80/443 desde 0.0.0.0/0
- SG-APP: TCP 80, 3001-3004 desde SG-ALB
- SG-DATA: TCP 3306 desde SG-APP

### 3. EC2 MySQL (subred privada DATA AZ1a)
- t4g.small, Amazon Linux 2023 ARM
- User data: instalar MySQL server
- Ejecutar init.sql (BD freshbox, 5 productos)
- Cifrado EBS habilitado

### 4. AWS Backup (DR)
- Plan de backup para EC2 MySQL
- Frecuencia diaria, retencion 7 dias

### 5. EC2 APP-1 (subred privada APP AZ1a)
- t4g.small, Amazon Linux 2023 ARM
- User data: instalar Docker + Compose
- IAM: LabInstanceProfile
- Cifrado EBS

### 6. EC2 APP-2 (subred privada APP AZ1b)
- Misma config que APP-1

### 7. ECR (5 repositorios)
- freshbox-frontend
- freshbox-get-products
- freshbox-create-product
- freshbox-update-product
- freshbox-delete-product

### 8. Build + Push imagenes (ARM64)
- Desde PC local con Docker Desktop
- Ejecutar scripts/ecr-push.sh

### 9. Deploy contenedores en ambas EC2 APP
- Via Session Manager
- Ejecutar scripts/deploy-containers.sh (ajustar DB_HOST)
- O usar docker-compose.aws.yml

### 10. ALB + Target Group
- Target Group: HTTP puerto 80, ambas EC2 APP
- ALB: internet-facing, subredes publicas, SG-ALB
- Health check: /

### 11. Validacion
- curl http://<ALB-DNS>/api/products → 5 productos
- Frontend via ALB → CRUD funcional
- Verificar ambas EC2 con docker ps (5 contenedores c/u)

---

## Criterios de evaluacion docente

| Aspecto | Verificar |
|---------|-----------|
| VPC correcta | 6 subredes, Multi-AZ, IGW, NAT GW |
| SG encadenados | ALB→APP→DATA, minimo privilegio |
| EC2 MySQL funcional | BD poblada, solo accesible desde SG-APP |
| AWS Backup | Plan activo para EC2 MySQL |
| 2 EC2 APP Multi-AZ | Contenedores corriendo en ambas |
| ECR con imagenes | 5 repos con imagenes ARM64 |
| ALB funcional | 2 targets healthy, DNS accesible |
| CRUD completo | GET, POST, PUT, DELETE operativos |
| Frontend | Interfaz web funcional via ALB |
| Cifrado | EBS encryption en EC2 APP y DATA |

---

2026 - Disenador: Ignacio A. Pastenet M.
