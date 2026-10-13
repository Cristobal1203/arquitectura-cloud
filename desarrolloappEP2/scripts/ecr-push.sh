#!/bin/bash
# FreshBox SpA - Build y Push imagenes a ECR (EP2 - EKS)
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

REPOS=("freshbox-frontend" "freshbox-get-products" "freshbox-create-product" "freshbox-update-product" "freshbox-delete-product")
for REPO in "${REPOS[@]}"; do aws ecr create-repository --repository-name $REPO --region $REGION 2>/dev/null || true; done

docker build --platform linux/arm64 -t freshbox-frontend ./microservicioEKSFrontend
docker build --platform linux/arm64 -t freshbox-get-products ./microserviciosEKSBackend/get-products
docker build --platform linux/arm64 -t freshbox-create-product ./microserviciosEKSBackend/create-product
docker build --platform linux/arm64 -t freshbox-update-product ./microserviciosEKSBackend/update-product
docker build --platform linux/arm64 -t freshbox-delete-product ./microserviciosEKSBackend/delete-product

for REPO in "${REPOS[@]}"; do
    docker tag $REPO $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
    docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
done
echo "=== Push EP2 completado ==="
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
