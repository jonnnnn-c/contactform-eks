output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repo to push the app image to (empty if security module disabled)."
  value       = var.enable_security_controls ? module.security[0].ecr_repository_url : ""
}

output "configure_kubectl" {
  description = "Run this to get a kubeconfig for the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
