
terraform {
  backend "s3" {
    bucket   = "infra-prod-sto-object-tf01"
    key      = "infra-production-storage.tfstate"
    region   = "rbx"

    endpoints = {
      s3 = "https://s3.rbx.io.cloud.ovh.net"
    }

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

