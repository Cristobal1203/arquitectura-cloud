# FreshBox SpA — Plataforma de Catalogo Online (EP1)

## Descripcion

Aplicacion CRUD de productos organicos para FreshBox SpA. Arquitectura de 3 capas con EC2 + Docker + MySQL, alta disponibilidad Multi-AZ con ALB y Auto Scaling.

## Arquitectura EP1 (3 Capas - EC2 + Docker)

| Capa | Componente | Servicio AWS |
|------|-----------|--------------|
| Publica | ALB | Application Load Balancer |
| Privada APP | 2x EC2 t4g.small + Docker (5 contenedores) | EC2 Multi-AZ |
| Privada DATA | EC2 t4g.small + MySQL | EC2 + AWS Backup |
| Registro | 5 imagenes Docker | Amazon ECR |
| Seguridad | Firewalls por capa | Security Groups |

## Microservicios (5 contenedores Docker)

| Contenedor | Puerto | Endpoint | Metodo |
|------------|--------|----------|--------|
| frontend | 80 | / | - |
| get-products | 3001 | /api/products | GET |
| create-product | 3002 | /api/products | POST |
| update-product | 3003 | /api/products/:id | PUT |
| delete-product | 3004 | /api/products/:id | DELETE |

## Estructura de Archivos

```
desarrolloappEP1/
├── README.md
├── docker-compose.yml              (prueba local)
├── init.sql                        (BD freshbox + 5 productos organicos)
├── microservicioFrontend/
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── index.html
│   ├── css/styles.css
│   └── js/app.js
├── microserviciosBackend/
│   ├── get-products/  (Dockerfile, package.json, index.js)
│   ├── create-product/
│   ├── update-product/
│   └── delete-product/
└── scripts/
    ├── user-data-ec2.sh
    ├── ecr-push.sh
    ├── deploy-containers.sh
    └── guia-docente-ep1.md         (guia paso a paso - referencia docente)
```

## Variables de Entorno

| Variable | Valor local | Valor AWS |
|----------|-------------|-----------|
| DB_HOST | db | (IP privada EC2 MySQL) |
| DB_USER | alumno | alumno |
| DB_PASS | alumno123 | alumno123 |
| DB_NAME | freshbox | freshbox |
| DB_PORT | 3306 | 3306 |

## Datos de Prueba

5 productos organicos FreshBox:
1. Manzana organica 1kg
2. Lechuga hidroponica
3. Granola artesanal 500g
4. Jugo natural naranja 1L
5. Mix frutos secos 250g

## Prueba Local

```bash
cd desarrolloappEP1/
docker compose build
docker compose up -d
docker compose ps
```

- Frontend: http://localhost:8080
- API: http://localhost:3001/api/products

## Pruebas CRUD (PowerShell)

```powershell
Invoke-RestMethod http://localhost:3001/api/products
Invoke-RestMethod -Method POST -Uri http://localhost:3002/api/products -ContentType "application/json" -Body '{"nombre":"Quinoa organica 500g","descripcion":"Quinoa premium","precio":4990,"stock":80,"categoria":"Granos"}'
Invoke-RestMethod -Method PUT -Uri http://localhost:3003/api/products/1 -ContentType "application/json" -Body '{"nombre":"Manzana organica 2kg","descripcion":"Manzana roja premium","precio":5990,"stock":60,"categoria":"Frutas"}'
Invoke-RestMethod -Method DELETE -Uri http://localhost:3004/api/products/6
```

## Detener

```bash
docker compose down -v
```

---

2026 - Disenador: Ignacio A. Pastenet M.
