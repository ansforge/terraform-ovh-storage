terraform {
  required_providers {
    ovh   = { source = "ovh/ovh", version = ">= 2.11.0" }
    vault = { source = "hashicorp/vault", version = ">= 3.25.0" }
  }
}

provider "vault" {
  skip_child_token = true
}

data "vault_generic_secret" "ovh_auth" {
  path = "iacrunner-outils/ovh_key"
}

provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = data.vault_generic_secret.ovh_auth.data["OVH_APPLICATION_KEY"]
  application_secret = data.vault_generic_secret.ovh_auth.data["OVH_APPLICATION_SECRET"]
  consumer_key       = data.vault_generic_secret.ovh_auth.data["OVH_CONSUMER_KEY"]
}

resource "ovh_cloud_project_storage" "tfstate" {
  service_name = var.service_name
  region_name  = "EU-WEST-PAR"    # ← Paris 3-AZ
  name         = var.bucket_prod_paris

  lifecycle {
    prevent_destroy = true
  }
}
