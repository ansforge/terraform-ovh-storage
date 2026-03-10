output "s3_access_key" {
  value = ovh_cloud_project_user_s3_credential.s3_creds.access_key_id
}

output "s3_secret_key" {
  value     = ovh_cloud_project_user_s3_credential.s3_creds.secret_access_key
  sensitive = true
}

output "openstack_username" {
  value = ovh_cloud_project_user.s3_user.username
}

output "openstack_password" {
  value     = ovh_cloud_project_user.s3_user.password
  sensitive = true
}
