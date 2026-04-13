terraform {
  backend "s3" {
    bucket = "infra-outils-sto-object-tf01"
    key    = "infra-outils-storage.tfstate"
    region = "eu-west-par"                                  # minuscules pour le client S3
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net/"      # minuscules pour le DNS
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

