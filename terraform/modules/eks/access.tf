# --- Cluster access for the deploying principal ------------------------------
# With authentication_mode = "API_AND_CONFIG_MAP", access is granted through EKS
# *access entries*, not implicitly to the cluster creator. Without this, kubectl
# returns 401 ("the server has asked for the client to provide credentials").
# We look up whoever is running Terraform and grant them cluster admin, so the
# same identity can immediately run kubectl/helm (used by the Ansible deploy).
data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "deployer_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.deployer]
}
