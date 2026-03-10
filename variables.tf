variable "service_name" {
  description = "ID du projet Public Cloud OVH (ex: 2b264def...)"
  type        = string
}

variable "bucket_prod_paris" {
  description = "Nom du bucket S3 à créer pour servir de backend Terraform"
  type        = string
}
