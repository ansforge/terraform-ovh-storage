# 🗄️ terraform-ovh-storage

**Gestion du stockage objet S3 OVH Cloud et des credentials associés via Terraform — ANS Forge**

Ce dépôt Terraform provisionne et gère l'infrastructure de stockage objet (S3 compatible) sur OVH Public Cloud. Il crée les buckets S3, les utilisateurs de service, les credentials, les policies d'accès, et stocke automatiquement les secrets dans **HashiCorp Vault**.

---

## 📑 Table des matières

- [Architecture](#-architecture)
- [Prérequis](#-prérequis)
- [Arborescence du projet](#-arborescence-du-projet)
- [Branches et environnements](#-branches-et-environnements)
- [Providers utilisés](#-providers-utilisés)
- [Module storage](#-module-storage)
- [Bootstrap (initialisation)](#-bootstrap-initialisation)
- [Variables](#-variables)
- [Backend S3 (state distant)](#-backend-s3-state-distant)
- [Commandes de lancement](#-commandes-de-lancement)
- [Commandes de test et vérification](#-commandes-de-test-et-vérification)
- [Gestion des secrets (Vault)](#-gestion-des-secrets-vault)
- [Flux de déploiement](#-flux-de-déploiement)
- [Dépannage](#-dépannage)
- [Contribution](#-contribution)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     HashiCorp Vault                              │
│  ┌─────────────────────┐  ┌──────────────────────────────────┐  │
│  │ iacrunner-*/ovh_key  │  │ iacrunner-*/aws_key             │  │
│  │ (OVH API Keys)      │  │ (S3 Access/Secret Key)           │  │
│  └─────────────────────┘  └──────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ iacrunner-*/openstack_key                                │   │
│  │ (OpenStack App Credential ID/Secret)                     │   │
│  └──────────────────────────────────────────────────────────┘   │
└───────────────────────────────┬──────────────��──────────────────┘
                                │ lecture / écriture
                                ▼
┌───────────────────────────────────────────────────────────────┐
│                    Terraform (ce repo)                         │
│  main.tf → module "all_in_one_storage"                        │
│            └── modules/storage/                               │
│                 ├── Utilisateur S3 + credentials              │
│                 ├── Utilisateur OpenStack + app credential    │
│                 ├── Bucket S3 (versioning + encryption)       │
│                 ├── Policy S3                                 │
│                 └── Secrets → Vault                           │
└───────────────────────────────┬───────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────┐
│                   OVH Public Cloud                             │
│  ┌──────────────┐  ┌��─────────────┐  ┌────────────────────┐  │
│  │ Object Store │  │ Cloud Users  │  │ OpenStack Keystone │  │
│  │ (S3 Bucket)  │  │ (S3 + OS)    │  │ (App Credentials)  │  │
│  └──────────────┘  └──────────────┘  └────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

---

## 📋 Prérequis

| Outil | Version | Description |
|---|---|---|
| **Terraform** | ≥ 1.5 | Infrastructure as Code |
| **HashiCorp Vault** | Accès actif | Stockage des secrets (OVH keys, AWS keys, OpenStack keys) |
| **OVH API Keys** | Créées via OVH Manager | `APPLICATION_KEY`, `APPLICATION_SECRET`, `CONSUMER_KEY` |
| **Compte OVH Public Cloud** | Projet actif | Avec le `service_name` (Project ID) |

### Variables d'environnement requises

```bash
# Vault
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="hvs.xxxxx"  # ou méthode d'auth configurée

# Backend S3 (pour le state Terraform)
export AWS_ACCESS_KEY_ID="<s3_access_key>"
export AWS_SECRET_ACCESS_KEY="<s3_secret_key>"
```

> ⚠️ Les credentials OVH ne sont **pas** en variables d'environnement. Elles sont lues directement depuis **Vault** par le provider OVH.

---

## 🗂️ Arborescence du projet

```
terraform-ovh-storage/
├── main.tf                          # Point d'entrée : providers + appel module storage
├── backend.tf                       # Configuration backend S3 distant (tfstate)
├── variables.tf                     # Variables racine (service_name, bucket, region)
├── storage.tfvars                   # Valeurs des variables pour l'environnement
├── .terraform.lock.hcl              # Verrouillage des versions des providers
├── .gitignore                       # Exclusion .terraform/ et *.tfstate*
├── modules/
│   └── storage/
│       ├── main.tf                  # Ressources : users, bucket, policy, vault secrets
│       ├── variables.tf             # Variables du module (service_name, bucket_name, region)
│       └── outputs.tf               # Outputs : clés S3, credentials OpenStack
├── terraform-bootstrap/
│   ├── main.tf                      # Création initiale du bucket de backend (tfstate)
│   ├── variables.tf                 # Variables bootstrap
│   └── .terraform.lock.hcl
└── README.md
```

---

## 🌿 Branches et environnements

Ce repo utilise **une branche par environnement** :

| Branche | Environnement | Vault Path | Région OVH | Bucket tfstate |
|---|---|---|---|---|
| `amont` | Pré-production | `iacrunner-amont/*` | `SBG` (Strasbourg) | `infra-amont-sto-object-tf01` |
| `prod` | Production | `iacrunner-prod/*` | `RBX` (Roubaix) | `infra-prod-sto-object-tf01` |
| `main` | — | — | — | Branche par défaut (documentation) |

### Différences entre branches

| Paramètre | `amont` | `prod` |
|---|---|---|
| `service_name` | `a5a3658023e146e78a22afd04601b813` | `2b264defd5244f52b8edbd6c9239a325` |
| `bucket_name` | `infra-amont-sto-object-tf01` | `infra-prod-sto-object-tf01` |
| `region_name` | `SBG` | `RBX` |
| Vault path | `iacrunner-amont/` | `iacrunner-prod/` |
| Backend S3 endpoint | `s3.sbg.io.cloud.ovh.net` | `s3.rbx.io.cloud.ovh.net` |
| Bucket versioning | ✅ Activé | ❌ Non configuré |
| Bucket encryption | ✅ AES256 | ❌ Non configuré |

---

## 🔌 Providers utilisés

| Provider | Source | Version | Usage |
|---|---|---|---|
| **ovh** | `ovh/ovh` | `>= 2.11.0` | Gestion des ressources OVH (users, buckets, policies) |
| **vault** | `hashicorp/vault` | `>= 3.25.0` | Lecture/écriture des secrets dans Vault |
| **openstack** | `terraform-provider-openstack/openstack` | latest | Création d'application credentials OpenStack |
| **aws** | `hashicorp/aws` | `>= 5.0.0` | Backend S3 compatible (branche prod uniquement) |

---

## 📦 Module storage

### `modules/storage/`

Le module **all-in-one** qui provisionne l'intégralité de l'infrastructure de stockage.

#### Ressources créées

| # | Ressource | Type | Description |
|---|---|---|---|
| 1 | `ovh_cloud_project_user.s3_user` | Utilisateur OVH | Utilisateur de service S3 avec rôle `objectstore_operator` |
| 2 | `ovh_cloud_project_user_s3_credential.s3_creds` | Credential S3 | Access Key / Secret Key pour l'accès S3 |
| 3 | `ovh_cloud_project_user.os_user` | Utilisateur OVH | Utilisateur OpenStack avec rôles `compute_operator`, `network_operator`, `administrator` |
| 4 | `openstack_identity_application_credential_v3.os_app_cred` | App Credential | Credential OpenStack pour Terraform (via provider dynamique) |
| 5 | `ovh_cloud_project_storage.this` | Bucket S3 | Bucket de stockage objet (versioning + encryption sur amont) |
| 6 | `ovh_cloud_project_user_s3_policy.s3_policy` | Policy S3 | Autorise `s3:*` sur le bucket créé |
| 7 | `vault_generic_secret.aws_key` | Secret Vault | Stocke `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY` |
| 8 | `vault_generic_secret.openstack_key` | Secret Vault | Stocke `OS_AUTH_URL`, `OS_REGION_NAME`, `OS_APPLICATION_CREDENTIAL_ID/SECRET` |

#### Variables du module

| Variable | Type | Description |
|---|---|---|
| `service_name` | `string` | ID du projet Public Cloud OVH |
| `bucket_name` | `string` | Nom du bucket S3 à créer |
| `region_name` | `string` | Région OVH (SBG, RBX, GRA...) — branche `amont` uniquement |

#### Outputs

| Output | Sensible | Description |
|---|---|---|
| `s3_access_key` | Non | Access Key ID de l'utilisateur S3 |
| `s3_secret_key` | **Oui** | Secret Access Key de l'utilisateur S3 |
| `openstack_username` | Non | Username de l'utilisateur OpenStack |
| `openstack_password` | **Oui** | Password de l'utilisateur OpenStack |

---

## 🥾 Bootstrap (initialisation)

### `terraform-bootstrap/`

Ce sous-dossier sert à **créer le bucket S3 qui hébergera le tfstate** (problème de la poule et l'œuf). Il ne doit être exécuté qu'**une seule fois** par environnement.

#### Ce qu'il fait

1. Lit les credentials OVH depuis Vault (`iacrunner-*/ovh_key`)
2. Crée un bucket S3 OVH avec `prevent_destroy = true` (protection contre la suppression)
3. Ce bucket sera ensuite utilisé comme backend S3 dans `backend.tf`

#### Commandes bootstrap

```bash
cd terraform-bootstrap/

# Initialiser (pas de backend distant, state local)
terraform init

# Planifier
terraform plan -var-file="../storage.tfvars"

# Appliquer (UNE SEULE FOIS)
terraform apply -var-file="../storage.tfvars"
```

> ⚠️ **Ne jamais `terraform destroy` le bootstrap** — le bucket contient les states de tous les projets.

---

## 📝 Variables

### Variables racine (`variables.tf`)

| Variable | Type | Description | Exemple |
|---|---|---|---|
| `service_name` | `string` | ID du projet Public Cloud OVH | `a5a3658023e146e78a22afd04601b813` |
| `bucket_prod_paris` | `string` | Nom du bucket S3 | `infra-amont-sto-object-tf01` |
| `region_name` | `string` | Région OVH | `SBG` (amont uniquement) |

### Fichier de variables (`storage.tfvars`)

**Branche `amont`** :
```hcl
service_name      = "a5a3658023e146e78a22afd04601b813"
bucket_prod_paris = "infra-amont-sto-object-tf01"
region_name       = "SBG"
```

**Branche `prod`** :
```hcl
service_name      = "2b264defd5244f52b8edbd6c9239a325"
bucket_prod_paris = "infra-prod-sto-object-tf01"
```

---

## 💾 Backend S3 (state distant)

Le state Terraform est stocké dans un bucket S3 OVH (créé par le bootstrap).

### Configuration (`backend.tf`)

**Branche `amont`** :
```hcl
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
```

**Branche `prod`** :
```hcl
terraform {
  backend "s3" {
    bucket = "infra-prod-sto-object-tf01"
    key    = "infra-production-storage.tfstate"
    region = "rbx"
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
```

---

## 🚀 Commandes de lancement

### Déploiement standard

```bash
# 1. Se positionner sur la branche de l'environnement cible
git checkout amont   # ou prod

# 2. Configurer les variables d'environnement
export VAULT_ADDR="https://vault.example.com"
export AWS_ACCESS_KEY_ID="<s3_access_key>"
export AWS_SECRET_ACCESS_KEY="<s3_secret_key>"

# 3. Initialiser Terraform (télécharge les providers, configure le backend)
terraform init

# 4. Planifier les changements
terraform plan -var-file="storage.tfvars"

# 5. Appliquer les changements
terraform apply -var-file="storage.tfvars"
```

### Destruction (⚠️ DANGER)

```bash
# Planifier la destruction
terraform plan -destroy -var-file="storage.tfvars"

# Détruire les ressources
terraform destroy -var-file="storage.tfvars"
```

> ⚠️ **Attention** : La destruction supprimera les utilisateurs, credentials, bucket et secrets Vault. Les autres projets Terraform qui dépendent de ces credentials seront impactés.

### Cibler une ressource spécifique

```bash
# Re-créer uniquement l'utilisateur S3
terraform apply -var-file="storage.tfvars" -target="module.all_in_one_storage.ovh_cloud_project_user.s3_user"

# Re-créer uniquement le secret Vault AWS
terraform apply -var-file="storage.tfvars" -target="module.all_in_one_storage.vault_generic_secret.aws_key"
```

---

## 🧪 Commandes de test et vérification

```bash
# Valider la syntaxe des fichiers Terraform
terraform validate

# Formater le code Terraform (vérification)
terraform fmt -check -recursive

# Formater le code Terraform (correction automatique)
terraform fmt -recursive

# Afficher le state actuel
terraform state list

# Afficher le détail d'une ressource dans le state
terraform state show module.all_in_one_storage.ovh_cloud_project_storage.this

# Afficher les outputs
terraform output
terraform output -json

# Afficher la clé secrète S3 (sensible)
terraform output s3_secret_key

# Rafraîchir le state (sync avec l'infrastructure réelle)
terraform refresh -var-file="storage.tfvars"

# Visualiser le graphe de dépendances
terraform graph | dot -Tpng > graph.png

# Planifier en mode détaillé
terraform plan -var-file="storage.tfvars" -detailed-exitcode
# Exit code 0 = pas de changement
# Exit code 1 = erreur
# Exit code 2 = changements détectés
```

### Vérification des secrets dans Vault

```bash
# Lire les credentials AWS/S3
vault kv get iacrunner-amont/aws_key

# Lire les credentials OpenStack
vault kv get iacrunner-amont/openstack_key

# Lire les clés OVH
vault kv get iacrunner-amont/ovh_key
```

### Tester l'accès S3

```bash
# Avec les credentials stockées dans Vault
export AWS_ACCESS_KEY_ID=$(vault kv get -field=AWS_ACCESS_KEY_ID iacrunner-amont/aws_key)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -field=AWS_SECRET_ACCESS_KEY iacrunner-amont/aws_key)

# Lister les buckets
aws s3 ls --endpoint-url https://s3.sbg.io.cloud.ovh.net/

# Lister le contenu du bucket
aws s3 ls s3://infra-amont-sto-object-tf01/ --endpoint-url https://s3.sbg.io.cloud.ovh.net/
```

---

## 🔐 Gestion des secrets (Vault)

### Secrets créés automatiquement

| Chemin Vault | Clés | Source |
|---|---|---|
| `iacrunner-*/ovh_key` | `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` | Pré-existant (créé manuellement) |
| `iacrunner-*/aws_key` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Créé par le module storage |
| `iacrunner-*/openstack_key` | `OS_AUTH_URL`, `OS_REGION_NAME`, `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET` | Créé par le module storage |

### Flux des secrets

```
OVH Manager → (manuel) → Vault: ovh_key
                                   ↓ (lecture)
                              Terraform
                                   ↓ (écriture)
                         Vault: aws_key + openstack_key
                                   ↓ (lecture par d'autres projets)
                         terraform-ovh-infra, ansible-ovh, etc.
```

---

## 📋 Flux de déploiement

### Première installation (nouvel environnement)

```
1. Créer les API Keys OVH (Manager OVH)
       ↓
2. Stocker les keys dans Vault (iacrunner-*/ovh_key)
       ↓
3. Bootstrap : créer le bucket de tfstate
   cd terraform-bootstrap && terraform apply -var-file="../storage.tfvars"
       ↓
4. Déployer le module storage
   cd .. && terraform init && terraform apply -var-file="storage.tfvars"
       ↓
5. Les credentials S3 et OpenStack sont maintenant dans Vault
       ↓
6. Les autres projets Terraform peuvent utiliser ces credentials
```

### Mise à jour courante

```
1. Modifier les fichiers .tf sur la branche appropriée (amont/prod)
       ↓
2. terraform plan -var-file="storage.tfvars"  → Vérifier les changements
       ↓
3. terraform apply -var-file="storage.tfvars" → Appliquer
       ↓
4. Merger vers main si nécessaire
```

---

## 🔧 Dépannage

### Problèmes courants

| Problème | Cause probable | Solution |
|---|---|---|
| `Error: Failed to get existing workspaces` | Backend S3 inaccessible | Vérifier `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` et l'endpoint S3 |
| `Error: Vault connection error` | Vault non joignable | Vérifier `VAULT_ADDR` et le token Vault |
| `Error: 401 Unauthorized (OVH)` | API Keys OVH expir��es ou invalides | Régénérer les keys dans le Manager OVH et mettre à jour Vault |
| `Error: openstack_identity_application_credential_v3` | Utilisateur OS pas encore provisionné | Relancer `terraform apply`, l'utilisateur sera créé avant le credential |
| `Error: prevent_destroy` sur le bucket bootstrap | Protection activée | Ne jamais détruire le bucket de backend ; commenter `prevent_destroy` **uniquement** si absolument nécessaire |
| `Error: bucket already exists` | Bucket déjà créé (bootstrap déjà exécuté) | Importer la ressource : `terraform import ovh_cloud_project_storage.tfstate <bucket_name>` |
| State lock | Autre process Terraform en cours | Attendre ou forcer : `terraform force-unlock <lock_id>` |

### Commandes de diagnostic

```bash
# Vérifier la connexion Vault
vault status
vault token lookup

# Vérifier les providers installés
terraform providers

# Vérifier le backend
terraform state pull | jq '.serial'

# Debug complet
TF_LOG=DEBUG terraform plan -var-file="storage.tfvars" 2>&1 | tee debug.log
```

---

## 🤝 Contribution

1. Se positionner sur la branche de l'environnement :
   ```bash
   git checkout amont  # pré-production
   git checkout prod   # production
   ```
2. Créer une branche feature si nécessaire :
   ```bash
   git checkout -b feature/ajout-bucket-logs amont
   ```
3. Valider avec `terraform validate` et `terraform fmt`
4. Planifier avec `terraform plan` pour vérifier l'impact
5. Créer une Pull Request vers la branche cible

### Conventions

- **Nommage des buckets** : `infra-<env>-sto-object-<usage><num>` (ex: `infra-prod-sto-object-tf01`)
- **Nommage des utilisateurs** : `svc-terraform-<type>` (ex: `svc-terraform-aws`, `svc-terraform-openstack`)
- **Vault paths** : `iacrunner-<env>/<secret_type>` (ex: `iacrunner-prod/aws_key`)
- **Branche par défaut** : `main` (documentation), `amont` (dev/preprod), `prod` (production)

---

## 📄 Licence

*Non spécifiée — Consulter l'organisation [ANS Forge](https://github.com/ansforge) pour plus d'informations.*

---

> **Maintenu par l'équipe Infrastructure ANS Forge** — G
