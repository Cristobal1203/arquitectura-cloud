# FreshBox SpA — Migracion a EKS + RDS Multi-AZ (EP2)

## Descripcion

Migracion de FreshBox desde EC2+Docker (EP1) hacia Amazon EKS (5 pods) y RDS MySQL Multi-AZ. Misma funcionalidad CRUD, plataforma gestionada con orquestacion.

## Arquitectura EP2

| Capa | Componente | Servicio AWS |
|------|-----------|--------------|
| Publica | ALB Ingress | ALB (creado por Ingress Controller) |
| Privada APP | EKS Cluster + Node Group | t4g.small, 2-4 nodos Multi-AZ |
| Privada APP | 5 Deployments x 2 replicas | 10 pods |
| Privada DATA | RDS MySQL Multi-AZ | db.t4g.small, failover automatico |
| Registro | 5 imagenes | ECR |
| Observabilidad | Container Insights | CloudWatch |

## Estructura

```
desarrolloappEP2/
├── README.md
├── init.sql                        (BD freshbox para RDS)
├── microserviciosEKSBackend/
│   ├── get-products/  (Dockerfile, index.js, package.json)
│   ├── create-product/
│   ├── update-product/
│   └── delete-product/
├── microservicioEKSFrontend/
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── index.html
│   ├── css/styles.css
│   └── js/app.js
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── frontend-deployment.yaml
│   ├── get-products-deployment.yaml
│   ├── create-product-deployment.yaml
│   ├── update-product-deployment.yaml
│   ├── delete-product-deployment.yaml
│   ├── ingress.yaml
│   └── hpa.yaml
└── scripts/
    ├── ecr-push.sh
    └── guia-docente-ep2.md
```

## Nota importante

El desarrollo es **autocontenido**: incluye todos los microservicios, frontend, manifiestos K8s y scripts necesarios para implementar sin depender de otra carpeta.

## Variables de Entorno

| Variable | Valor |
|----------|-------|
| DB_HOST | (RDS endpoint) |
| DB_USER | alumno |
| DB_PASS | alumno123 |
| DB_NAME | freshbox |
| DB_PORT | 3306 |

## Prueba local

Usar el docker-compose.yml de EP1 para validar que la app funciona antes de migrar a EKS.

---

2026 - Disenador: Ignacio A. Pastenet M.
