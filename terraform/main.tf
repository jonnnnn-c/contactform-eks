locals {
  name = "${var.project}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "./modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  single_nat_gateway = var.single_nat_gateway
  cluster_name       = local.name
}

module "iam" {
  source = "./modules/iam"

  name = local.name
}

module "eks" {
  source = "./modules/eks"

  name                        = local.name
  kubernetes_version          = var.kubernetes_version
  private_subnet_ids          = module.vpc.private_subnet_ids
  public_subnet_ids           = module.vpc.public_subnet_ids
  cluster_role_arn            = module.iam.cluster_role_arn
  node_role_arn               = module.iam.node_role_arn
  node_instance_types         = var.node_instance_types
  node_desired_size           = var.node_desired_size
  node_min_size               = var.node_min_size
  node_max_size               = var.node_max_size
  cluster_public_access_cidrs = var.cluster_public_access_cidrs
}

module "security" {
  source = "./modules/security"
  count  = var.enable_security_controls ? 1 : 0

  name                    = local.name
  region                  = var.region
  enable_threat_detection = var.enable_threat_detection
}
