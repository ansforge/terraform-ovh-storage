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
  role_names   = ["compute_operator", "network_operator", "administrator"]
}

# --- 2. CONFIGURATION PROVIDER DYNAMIQUE ---
# On crée un provider OpenStack qui utilise les identifiants de l'utilisateur tout juste créé
provider "openstack" {
  alias    = "new_user"
  auth_url = "https://auth.cloud.ovh.net/v3/"
  user_name = ovh_cloud_project_user.os_user.username
  password  = ovh_cloud_project_user.os_user.password
  tenant_id = var.service_name # Chez OVH, le service_name est le Project ID
}

# --- 3. CRÉATION DU CREDENTIAL (AVEC L'ALIAS) ---
resource "openstack_identity_application_credential_v3" "os_app_cred" {
  provider    = openstack.new_user # On utilise la session du nouvel utilisateur
  name        = "tf-app-credential"
  description = "Credential pour Terraform (Auto-généré)"
}

# --- 4. BUCKET & POLICY S3 ---
resource "ovh_cloud_project_storage" "this" {
  service_name = var.service_name
  region_name  = "RBX"
  name         = var.bucket_name
}

resource "ovh_cloud_project_user_s3_policy" "s3_policy" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.s3_user.id
  policy = jsonencode({
    Statement = [{
      Sid      = "AllowS3Access"
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["arn:aws:s3:::${var.bucket_name}", "arn:aws:s3:::${var.bucket_name}/*"]
    }]
  })
}

# --- 5. VAULT ---
resource "vault_generic_secret" "aws_key" {
  path = "iacrunner-prod/aws_key"
  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = ovh_cloud_project_user_s3_credential.s3_creds.access_key_id
    AWS_SECRET_ACCESS_KEY = ovh_cloud_project_user_s3_credential.s3_creds.secret_access_key
  })
}

resource "vault_generic_secret" "openstack_key" {
  path = "iacrunner-prod/openstack_key"
  data_json = jsonencode({
    OS_AUTH_URL                      = "https://auth.cloud.ovh.net/v3/"
    OS_REGION_NAME                   = "RBX"
    OS_APPLICATION_CREDENTIAL_ID     = openstack_identity_application_credential_v3.os_app_cred.id
    OS_APPLICATION_CREDENTIAL_SECRET = openstack_identity_application_credential_v3.os_app_cred.secret
  })
}
