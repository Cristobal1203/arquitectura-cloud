#!/bin/bash
# FreshBox SpA - Deploy contenedores en EC2 (EP1)
# Ejecutar DENTRO de EC2 APP via Session Manager
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DB_HOST="10.0.2.X"  # MODIFICAR: IP privada EC2 MySQL

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-frontend:latest
docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-get-products:latest
docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-create-product:latest
docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-update-product:latest
docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-delete-product:latest

docker stop freshbox-frontend freshbox-get-products freshbox-create-product freshbox-update-product freshbox-delete-product 2>/dev/null
docker rm freshbox-frontend freshbox-get-products freshbox-create-product freshbox-update-product freshbox-delete-product 2>/dev/null
docker network create freshbox-net 2>/dev/null

docker run -d --name freshbox-get-products --network freshbox-net -p 3001:3001 -e DB_HOST=$DB_HOST -e DB_USER=alumno -e DB_PASS=alumno123 -e DB_NAME=freshbox -e PORT=3001 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-get-products:latest
docker run -d --name freshbox-create-product --network freshbox-net -p 3002:3002 -e DB_HOST=$DB_HOST -e DB_USER=alumno -e DB_PASS=alumno123 -e DB_NAME=freshbox -e PORT=3002 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-create-product:latest
docker run -d --name freshbox-update-product --network freshbox-net -p 3003:3003 -e DB_HOST=$DB_HOST -e DB_USER=alumno -e DB_PASS=alumno123 -e DB_NAME=freshbox -e PORT=3003 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-update-product:latest
docker run -d --name freshbox-delete-product --network freshbox-net -p 3004:3004 -e DB_HOST=$DB_HOST -e DB_USER=alumno -e DB_PASS=alumno123 -e DB_NAME=freshbox -e PORT=3004 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-delete-product:latest
docker run -d --name freshbox-frontend --network freshbox-net -p 80:80 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-frontend:latest

docker ps
echo "=== Deploy EP1 completado ==="

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
