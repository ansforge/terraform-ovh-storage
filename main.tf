terraform {
  required_providers {
    ovh   = { source = "ovh/ovh", version = ">= 2.11.0" }
    vault = { source = "hashicorp/vault", version = ">= 3.25.0" }
  }
}

provider "vault" { skip_child_token = true }

data "vault_generic_secret" "ovh_auth" { path = "iacrunner-amont/ovh_key" }

provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = data.vault_generic_secret.ovh_auth.data["OVH_APPLICATION_KEY"]
  application_secret = data.vault_generic_secret.ovh_auth.data["OVH_APPLICATION_SECRET"]
  consumer_key       = data.vault_generic_secret.ovh_auth.data["OVH_CONSUMER_KEY"]
}

module "all_in_one_storage" {
  source       = "./modules/storage"
  service_name = var.service_name
  bucket_name  = var.bucket_prod_paris
  region_name  = var.region_name  
}
