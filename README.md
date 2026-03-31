Infrastructure OVHcloud - Storage & Identity (Amont)

Ce dépôt Terraform gère le socle de base de l'infrastructure OVHcloud : 
- le stockage S3 (Object Storage)
- le backend Terraform distant
- la gestion des identités (utilisateurs de service)
- la génération et sécurisation des credentials via Vault

🏗️ Structure du Projet

terraform-bootstrap/ : Dossier critique utilisé une seule fois pour créer le bucket S3 qui héberge le fichier d’état Terraform (.tfstate).

modules/storage/ : Module principal gérant :
- les utilisateurs OVH (S3 + OpenStack)
- le bucket applicatif
- les credentials
- les policies de sécurité
- l’intégration Vault

backend.tf : Configuration du backend distant (S3 OVH Object Storage).

main.tf : Point d’entrée Terraform appelant le module de stockage.

variables.tf : Déclaration des variables globales.

storage.tfvars : Valeurs des variables pour l’environnement.

🔑 Gestion des Identités (IAM)

L’infrastructure repose sur une séparation stricte des privilèges avec deux utilisateurs de service :

Utilisateur : svc-terraform-aws  
Description : Accès S3 uniquement  
Rôles OVH : objectstore_operator  

Utilisateur : svc-terraform-openstack  
Description : Gestion compute et réseau  
Rôles OVH : compute_operator, network_operator, administrator  

Sécurité :  
L’utilisateur OpenStack utilise des Application Credentials (ID/Secret) au lieu d’un mot de passe pour un usage automatisé sécurisé.

🔐 Intégration Vault

Les secrets sont automatiquement générés puis stockés dans HashiCorp Vault :

iacrunner-amont/aws_key :
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY

iacrunner-amont/openstack_key :
- OS_AUTH_URL
- OS_REGION_NAME
- OS_APPLICATION_CREDENTIAL_ID
- OS_APPLICATION_CREDENTIAL_SECRET

iacrunner-amont/ovh_key (pré-requis) :
- OVH_APPLICATION_KEY
- OVH_APPLICATION_SECRET
- OVH_CONSUMER_KEY

⚠️ Aucun secret n’est stocké en clair dans le repository.

🪣 Stockage S3 (OVH Object Storage)

Deux usages principaux :

1. Backend Terraform
- Bucket : infra-amont-sto-object-tf01
- Région : SBG
- Endpoint : https://s3.sbg.io.cloud.ovh.net/

2. Bucket applicatif
- Versioning activé
- Chiffrement AES256
- Policy S3 full access pour svc-terraform-aws

🚀 Ordre d’Exécution (IMPORTANT)

1. Bootstrap du backend Terraform (à faire UNE seule fois)

cd terraform-bootstrap

terraform init  
terraform apply \
  -var="service_name=<SERVICE_NAME>" \
  -var="bucket_prod_paris=infra-amont-sto-object-tf01"

👉 Cette étape crée le bucket qui va stocker le state Terraform.
👉 Sans ça, le backend ne fonctionnera pas.

---

2. Initialisation du projet principal

cd ..

terraform init

👉 Terraform utilise maintenant le backend S3 défini dans backend.tf

---

3. Déploiement de l’infrastructure

terraform plan -var-file="storage.tfvars"  
terraform apply -var-file="storage.tfvars"

---

🔧 Variables

storage.tfvars :

service_name      = "a5a3658023e146e78a22afd04601b813"
bucket_prod_paris = "infra-amont-sto-object-tf01"
region_name       = "SBG"

---

🔐 Pré-requis

1. Vault accessible :

export VAULT_ADDR=https://vault.xxx

2. Secret OVH présent :

path : iacrunner-amont/ovh_key

3. Permissions Vault :
- lecture ovh_key
- écriture aws_key / openstack_key

---

🧪 Vérifications post-déploiement

Vérifier le bucket :
ovh storage list

Vérifier les secrets Vault :
vault kv get iacrunner-amont/aws_key  
vault kv get iacrunner-amont/openstack_key  

---

🛡️ Sécurité

- Backend distant (pas de state local)
- Credentials dynamiques
- Secrets stockés uniquement dans Vault
- Séparation des rôles (S3 vs OpenStack)
- prevent_destroy activé sur le bucket backend

---

⚠️ Points d’attention

- Toujours exécuter terraform-bootstrap en premier
- Ne jamais supprimer le bucket de backend
- Vérifier les accès Vault avant exécution
- Vérifier la connectivité vers l’endpoint S3 OVH

---

🔄 Améliorations possibles

- Rotation automatique des credentials
- Ajout de lifecycle policies S3
- Multi-environnements (dev / prod)
- Intégration CI/CD (GitLab / GitHub Actions)

---

👨‍💻 Auteur

Infrastructure Terraform OVHcloud – Projet d’industrialisation du provisioning et de la gestion des accès.
