terraform {
  required_providers {
    ovh       = { source = "ovh/ovh" }
    vault     = { source = "hashicorp/vault" }
    openstack = { source = "terraform-provider-openstack/openstack" }
  }
}

# --- 1. UTILISATEURS OVH ---
resource "ovh_cloud_project_user" "s3_user" {
  service_name = var.service_name
  description  = "svc-terraform-aws"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "s3_creds" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.s3_user.id
}

resource "ovh_cloud_project_user" "os_user" {
  service_name = var.service_name
  description  = "svc-terraform-openstack"

  # ✔️ rôles OK
  role_names = [
    "compute_operator",
    "network_operator",
    "administrator"
  ]
}

# --- 2. PROVIDER OPENSTACK (CORRIGÉ AVEC ALIAS) ---
provider "openstack" {
  alias     = "new_user"
  auth_url  = "https://auth.cloud.ovh.net/v3/"
  user_name = ovh_cloud_project_user.os_user.username
  password  = ovh_cloud_project_user.os_user.password
  tenant_id = var.service_name
}

# --- 3. APPLICATION CREDENTIAL (CORRIGÉ) ---
resource "openstack_identity_application_credential_v3" "os_app_cred" {
  provider    = openstack.new_user
  name        = "tf-app-credential"
  description = "Credential pour Terraform (Auto-généré)"
}

# --- 4. BUCKET S3 ---
resource "ovh_cloud_project_storage" "this" {
  service_name = var.service_name
  region_name  = var.region_name
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }
}

# --- 5. POLICY S3 ---
resource "ovh_cloud_project_user_s3_policy" "s3_policy" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.s3_user.id

  policy = jsonencode({
    Statement = [{
      Sid    = "AllowS3Access"
      Effect = "Allow"
      Action = ["s3:*"]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}

# --- 6. VAULT : AWS KEYS ---
resource "vault_generic_secret" "aws_key" {
  path = "iacrunner-amont/aws_key"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = ovh_cloud_project_user_s3_credential.s3_creds.access_key_id
    AWS_SECRET_ACCESS_KEY = ovh_cloud_project_user_s3_credential.s3_creds.secret_access_key
  })
}

# --- 7. VAULT : OPENSTACK KEYS ---
resource "vault_generic_secret" "openstack_key" {
  path = "iacrunner-amont/openstack_key"

  data_json = jsonencode({
    OS_AUTH_URL                      = "https://auth.cloud.ovh.net/v3/"
    OS_REGION_NAME                   = var.region_name
    OS_APPLICATION_CREDENTIAL_ID     = openstack_identity_application_credential_v3.os_app_cred.id
    OS_APPLICATION_CREDENTIAL_SECRET = openstack_identity_application_credential_v3.os_app_cred.secret
  })
}
