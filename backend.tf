terraform {
  backend "s3" {
    bucket = "infra-amont-sto-object-tf01"
    key    = "infra-amont-storage.tfstate"
    region = "sbg"
    endpoints = {
      s3 = "https://s3.sbg.io.cloud.ovh.net/"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
