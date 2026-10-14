# Guia Docente — Implementacion EP2 (FreshBox SpA - EKS)

## Referencia para el docente — NO entregar al estudiante

| Campo | Valor |
|-------|-------|
| Caso | FreshBox SpA - Migracion a EKS + RDS Multi-AZ |
| Cluster | freshbox-cluster |
| Namespace | freshbox |
| Nodos | t4g.small, 2-4 Multi-AZ |
| RDS | db.t4g.small MySQL Multi-AZ |

---

## Pasos esperados

1. Crear/reutilizar VPC Multi-AZ (misma EP1 o nueva)
2. Crear Security Groups (SG-ALB, SG-EKS, SG-RDS)
3. Crear RDS MySQL Multi-AZ + ejecutar init.sql
4. Crear cluster EKS con eksctl (o consola)
5. Configurar kubectl
6. Reutilizar imagenes ECR de EP1 (o rebuild + push)
7. Actualizar manifiestos (ACCOUNT_ID, RDS_ENDPOINT)
8. kubectl apply (namespace, configmap, secret, deployments, services)
9. Instalar ALB Controller + aplicar ingress
10. Aplicar HPA
11. Habilitar Container Insights (si el lab lo permite, sino omitir)
12. Validar CRUD via ALB DNS

## Criterios de evaluacion

| Aspecto | Verificar |
|---------|-----------|
| EKS cluster activo | eksctl get cluster → ACTIVE |
| 2+ nodos Ready | kubectl get nodes |
| 10 pods Running | kubectl get pods -n freshbox (5x2) |
| RDS Multi-AZ | Consola RDS → Multi-AZ: Yes |
| ALB Ingress | kubectl get ingress → ADDRESS con DNS |
| HPA activo | kubectl get hpa -n freshbox |
| CRUD funcional | GET, POST, PUT, DELETE via ALB |
| Container Insights | CloudWatch → metricas por pod (si el lab lo permite, sino omitir y documentar teoricamente) |
| Seguridad | SG encadenados, cifrado RDS |

---

2026 - Disenador: Ignacio A. Pastenet M.
