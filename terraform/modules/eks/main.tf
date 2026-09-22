# --- KMS key used to encrypt Kubernetes Secrets at rest (envelope encryption) -
resource "aws_kms_key" "eks" {
  description             = "${var.name} EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${var.name}-eks-kms" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# --- Control-plane logging ---------------------------------------------------
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 90
}

# --- EKS cluster -------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  # All control-plane log types on (CIS / audit requirement).
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_public_access_cidrs
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [aws_cloudwatch_log_group.eks]
}

# --- OIDC provider for IRSA (IAM Roles for Service Accounts) ------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

# --- IRSA role for the EBS CSI driver (least privilege) ----------------------
# The aws-ebs-csi-driver addon needs AWS permissions to create/attach EBS
# volumes for PersistentVolumeClaims (e.g. the Postgres StatefulSet). We grant
# them via IRSA scoped to the driver's service account, not the node role.
locals {
  oidc_host = replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")
}

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# --- Managed node group (in PRIVATE subnets) ---------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"
  ami_type        = "AL2023_x86_64_STANDARD" # AL2 is retired; AL2023 is current
  disk_size       = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = { workload = "general" }
  tags   = { Name = "${var.name}-ng" }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# --- Core add-ons ------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = null
  depends_on    = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.this, aws_iam_role_policy_attachment.ebs_csi]
}
