#!/bin/bash
# FreshBox SpA - Build y Push imagenes a ECR (EP1)
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "=== Account: $ACCOUNT_ID | Region: $REGION ==="

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

REPOS=("freshbox-frontend" "freshbox-get-products" "freshbox-create-product" "freshbox-update-product" "freshbox-delete-product")
for REPO in "${REPOS[@]}"; do
    aws ecr create-repository --repository-name $REPO --region $REGION 2>/dev/null || echo "$REPO ya existe"
done

docker build --platform linux/arm64 -t freshbox-frontend ./microservicioFrontend
docker build --platform linux/arm64 -t freshbox-get-products ./microserviciosBackend/get-products
docker build --platform linux/arm64 -t freshbox-create-product ./microserviciosBackend/create-product
docker build --platform linux/arm64 -t freshbox-update-product ./microserviciosBackend/update-product
docker build --platform linux/arm64 -t freshbox-delete-product ./microserviciosBackend/delete-product

for REPO in "${REPOS[@]}"; do
    docker tag $REPO $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
    docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
done

echo "=== Push completado ==="

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
