variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" { type = list(string) }
variable "single_nat_gateway" {
  type    = bool
  default = true
}
variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags."
  type        = string
}
