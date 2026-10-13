############################################################
# TERRAFORM EP2 — FreshBox SpA: EKS + RDS Multi-AZ
# Complemento del main.tf (EP2)
# AWS Academy Learner Lab: usa LabRole, NO crea roles IAM propios
#
# Recursos definidos aqui:
#   - Variables EP2 (EKS)
#   - Tags de subredes para EKS + ALB Controller
#   - Security Group del control plane EKS
#   - aws_eks_cluster (freshbox-cluster)
#   - aws_eks_node_group (freshbox-nodes)
#   - Outputs EP2
#
# Recursos en main.tf:
#   - VPC, subredes, IGW, NAT Gateways, Route Tables
#   - Security Groups (SG-ALB, SG-EKS-Nodes, SG-RDS)
#   - ECR repositories (5)
#   - RDS MySQL Multi-AZ
############################################################

############################################################
# VARIABLES EP2
############################################################

variable "eks_cluster_name" {
  description = "Nombre del cluster EKS."
  type        = string
  default     = "freshbox-cluster"
}

variable "eks_kubernetes_version" {
  description = "Version de Kubernetes disponible en el lab (ej: 1.29 o 1.30)."
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_type" {
  description = "Instancia para nodos EKS. Pauta pide t4g.small; usar t3.small si ARM no esta disponible."
  type        = string
  default     = "t3.small"
}

variable "eks_node_ami_type" {
  description = "Tipo de AMI. AL2_x86_64 para t3.small. AL2_ARM_64 para t4g.small."
  type        = string
  default     = "AL2_x86_64"
}

variable "eks_node_min_size" {
  description = "Minimo de nodos en el Node Group (pauta pide min 2)."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximo de nodos en el Node Group (pauta pide max 4)."
  type        = number
  default     = 4
}

variable "eks_node_desired_size" {
  description = "Nodos deseados al iniciar."
  type        = number
  default     = 2
}

variable "eks_node_disk_size" {
  description = "Tamano del disco EBS de cada nodo en GB."
  type        = number
  default     = 20
}

############################################################
# TAGS OBLIGATORIOS EN SUBREDES PARA EKS + ALB CONTROLLER
#
# El AWS Load Balancer Controller lee estos tags para:
#   kubernetes.io/role/elb = 1          -> subredes PUBLICAS (ALB)
#   kubernetes.io/role/internal-elb = 1 -> subredes PRIVADAS (NLB)
#   kubernetes.io/cluster/<name> = shared -> subredes del cluster
#
# SIN estos tags el Ingress Controller no puede crear el ALB.
############################################################

resource "aws_ec2_tag" "public_subnet_elb" {
  count       = length(aws_subnet.public)
  resource_id = aws_subnet.public[count.index].id
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "app_subnet_internal_elb" {
  count       = length(aws_subnet.app)
  resource_id = aws_subnet.app[count.index].id
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster" {
  count       = length(aws_subnet.public)
  resource_id = aws_subnet.public[count.index].id
  key         = "kubernetes.io/cluster/${var.eks_cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "app_subnet_cluster" {
  count       = length(aws_subnet.app)
  resource_id = aws_subnet.app[count.index].id
  key         = "kubernetes.io/cluster/${var.eks_cluster_name}"
  value       = "shared"
}

############################################################
# SECURITY GROUP DEL CONTROL PLANE DE EKS
#
# EKS crea un ENI (interfaz de red) en tu VPC para el control plane.
# Este SG gestiona la comunicacion entre el control plane y los nodos:
#   443  : API Server -> nodos (kubelet)
#   10250: kubelet API (kubectl logs, exec, metrics)
############################################################

resource "aws_security_group" "eks_control_plane" {
  name        = "${var.project_name}-sg-eks-control-plane"
  description = "SG del control plane EKS - comunicacion API Server con nodos"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "HTTPS hacia nodos worker (kubelet)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description     = "Kubelet API en nodos (kubectl logs, exec)"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Trafico de retorno nodos -> API Server"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "${var.project_name}-sg-eks-control-plane" }
}

############################################################
# EKS CLUSTER
#
# Amazon EKS gestiona el control plane (API Server, etcd, scheduler).
# Tu solo gestionas: Node Groups, pods, deployments, servicios.
#
# Learner Lab:
#   - role_arn = LabRole (unico rol disponible)
#   - enabled_cluster_log_types = [] (sin logs para conservar presupuesto)
#   - endpoint_public_access = true  (acceso desde CloudShell y tu PC)
#   - endpoint_private_access = true (nodos se comunican internamente)
############################################################

data "aws_iam_role" "eks_cluster_role" {
  name = "LabRole"
}

resource "aws_eks_cluster" "freshbox" {
  name     = var.eks_cluster_name
  role_arn = data.aws_iam_role.eks_cluster_role.arn
  version  = var.eks_kubernetes_version

  vpc_config {
    # Subredes publicas (ALB del Ingress Controller) +
    # subredes privadas de app (nodos EKS)
    subnet_ids = concat(
      aws_subnet.public[*].id,
      aws_subnet.app[*].id
    )

    # SG de nodos EKS + SG de control plane
    security_group_ids = [
      aws_security_group.app.id,
      aws_security_group.eks_control_plane.id,
    ]

    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Sin logs para conservar presupuesto del Learner Lab
  enabled_cluster_log_types = []

  tags = { Name = var.eks_cluster_name }

  depends_on = [
    aws_ec2_tag.public_subnet_elb,
    aws_ec2_tag.app_subnet_internal_elb,
    aws_ec2_tag.public_subnet_cluster,
    aws_ec2_tag.app_subnet_cluster,
  ]
}

############################################################
# EKS NODE GROUP (Managed)
#
# Managed Node Groups = AWS gestiona el lifecycle de las EC2.
# Los nodos son instancias EC2 con kubelet instalado.
#
# Pauta EP2 pide:
#   - t4g.small (ARM), min 2 / max 4 nodos, Multi-AZ
#   - EBS cifrado (habilitado por defecto en managed NG)
#
# Learner Lab:
#   - t3.small (x86_64) mas compatible que t4g.small
#   - 2 nodos x 2 vCPU = 4 vCPU (bien bajo el limite de 32)
#   - 2 EC2 (bien bajo el limite de 9 instancias)
############################################################

resource "aws_eks_node_group" "freshbox" {
  cluster_name    = aws_eks_cluster.freshbox.name
  node_group_name = "freshbox-nodes"
  node_role_arn   = data.aws_iam_role.eks_cluster_role.arn

  # Subredes PRIVADAS de app: salen a Internet via NAT Gateway
  # para descargar imagenes ECR y updates, pero no son accesibles
  # directamente desde Internet.
  subnet_ids = aws_subnet.app[*].id

  instance_types = [var.eks_node_instance_type]
  ami_type       = var.eks_node_ami_type
  capacity_type  = "ON_DEMAND"
  disk_size      = var.eks_node_disk_size  # 20 GB EBS gp2

  scaling_config {
    desired_size = var.eks_node_desired_size  # 2 nodos iniciales
    min_size     = var.eks_node_min_size      # min 2 (uno por AZ)
    max_size     = var.eks_node_max_size      # max 4
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name                                                  = "freshbox-nodes"
    "k8s.io/cluster-autoscaler/${var.eks_cluster_name}"  = "owned"
    "k8s.io/cluster-autoscaler/enabled"                  = "true"
  }

  depends_on = [aws_eks_cluster.freshbox]
}

############################################################
# OUTPUTS EP2
############################################################

output "eks_cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.freshbox.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint HTTPS del API Server de EKS"
  value       = aws_eks_cluster.freshbox.endpoint
}

output "eks_kubernetes_version" {
  description = "Version de Kubernetes del cluster"
  value       = aws_eks_cluster.freshbox.version
}

output "eks_kubeconfig_command" {
  description = "Ejecuta este comando para configurar kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.freshbox.name}"
}

output "eks_node_group_status" {
  description = "Estado del Node Group (debe ser ACTIVE)"
  value       = aws_eks_node_group.freshbox.status
}

output "eks_node_instance_type_used" {
  description = "Tipo de instancia de los nodos"
  value       = var.eks_node_instance_type
}

output "eks_sg_control_plane_id" {
  description = "SG del control plane EKS"
  value       = aws_security_group.eks_control_plane.id
}

output "next_steps" {
  description = "Pasos siguientes despues de terraform apply"
  value       = <<-EOT

    === PASOS SIGUIENTES PARA EP2 ===

    1. Configurar kubectl:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name}

    2. Verificar nodos:
       kubectl get nodes

    3. Instalar AWS Load Balancer Controller (via Helm):
       helm repo add eks https://aws.github.io/eks-charts && helm repo update
       helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
         -n kube-system \
         --set clusterName=${var.eks_cluster_name} \
         --set region=${var.aws_region} \
         --set vpcId=$(terraform output -raw vpc_id)

    4. Obtener endpoint RDS -> actualizar k8s/configmap.yaml:
       terraform output rds_address

    5. Obtener ECR registry -> actualizar deployment YAMLs:
       terraform output ecr_registry
       terraform output ecr_repository_urls

    6. Aplicar manifiestos K8s (en orden):
       kubectl apply -f k8s/namespace.yaml
       kubectl apply -f k8s/configmap.yaml
       kubectl apply -f k8s/secret.yaml
       kubectl apply -f k8s/frontend-deployment.yaml
       kubectl apply -f k8s/get-products-deployment.yaml
       kubectl apply -f k8s/create-product-deployment.yaml
       kubectl apply -f k8s/update-product-deployment.yaml
       kubectl apply -f k8s/delete-product-deployment.yaml
       kubectl apply -f k8s/ingress.yaml
       kubectl apply -f k8s/hpa.yaml

    7. Verificar todo:
       kubectl get pods -n freshbox
       kubectl get ingress -n freshbox   <- aqui aparece el DNS del ALB
       kubectl get hpa -n freshbox

  EOT
}
