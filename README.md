# Infrastructure OVHcloud - Storage & Identity (Prod)

Ce dépôt Terraform gère le socle de base de l'infrastructure sur OVHcloud : le stockage S3 (backend Terraform) et la gestion des identités (utilisateurs de service).

## 🏗️ Structure du Projet

* `terraform-bootstrap/` : **Dossier critique.** Utilisé une seule fois pour créer le bucket S3 qui héberge le fichier d'état (`.tfstate`).
* `modules/storage/` : Module principal gérant les utilisateurs, le bucket applicatif et les politiques de sécurité.
* `backend.tf` : Configuration du stockage distant (S3) pour le state Terraform.
* `main.tf` : Point d'entrée appelant le module de stockage.

## 🔑 Gestion des Identités (IAM)

L'infrastructure repose sur la séparation des privilèges avec deux utilisateurs de service distincts :

| Utilisateur | Description | Rôles OVH |
| :--- | :--- | :--- |
| **svc-terraform-aws** | Accès S3 uniquement. | `ObjectStore operator` |
| **svc-terraform-openstack** | Gestion compute/réseau. | `Compute/Network operator`, `Administrator` |

> **Sécurité :** L'utilisateur OpenStack utilise des **Application Credentials** (ID/Secret) au lieu d'un mot de passe classique pour l'automatisation.

## 🔐 Intégration Vault

Les secrets générés sont automatiquement poussés dans HashiCorp Vault :
* `iacrunner-prod/aws_key` : Identifiants S3 (Access/Secret Key).
* `iacrunner-prod/openstack_key` : Identifiants OpenStack (App Credential ID/Secret).

## 🚀 Utilisation

### Pré-requis
1.  Avoir les clés d'API OVH dans Vault (`iacrunner-prod/ovh_key`).
2.  Charger les variables d'environnement pour le backend :
    ```bash
    export AWS_ACCESS_KEY_ID=$(vault kv get -field=AWS_ACCESS_KEY_ID iacrunner-prod/aws_key)
    export AWS_SECRET_ACCESS_KEY=$(vault kv get -field=AWS_SECRET_ACCESS_KEY iacrunner-prod/aws_key)
    ```

### Déploiement
```bash
terraform init
terraform apply -var-file="storage.tfvars"
