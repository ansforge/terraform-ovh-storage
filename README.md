# Infrastructure OVHcloud - Storage & Identity (Outils)

Ce dépôt Terraform gère le socle de base de l'infrastructure OVHcloud pour l'environnement **Outils** :
- le stockage S3 (Object Storage)
- le backend Terraform distant
- la gestion des identités (utilisateurs de service)
- la génération et sécurisation des credentials via Vault

---

## 🏗️ Structure du Projet

- **terraform-bootstrap/** : Dossier critique utilisé une seule fois pour créer le bucket S3 qui héberge le fichier d'état Terraform (`.tfstate`).

- **modules/storage/** : Module principal gérant :
  - les utilisateurs OVH (S3 + OpenStack)
  - le bucket applicatif
  - les credentials
  - les policies de sécurité
  - l'intégration Vault

- **backend.tf** : Configuration du backend distant (S3 OVH Object Storage, région Paris).
- **main.tf** : Point d'entrée Terraform appelant le module de stockage.
- **variables.tf** : Déclaration des variables globales.
- **storage.tfvars** : Valeurs des variables pour l'environnement.

---

## 🔑 Gestion des Identités (IAM)

L'infrastructure repose sur une séparation stricte des privilèges avec deux utilisateurs de service :

| Utilisateur | Description | Rôles OVH |
|---|---|---|
| `svc-terraform-aws` | Accès S3 uniquement | `objectstore_operator` |
| `svc-terraform-openstack` | Gestion compute et réseau | `compute_operator`, `network_operator`, `administrator` |

> **Sécurité** : L'utilisateur OpenStack utilise des Application Credentials (ID/Secret) au lieu d'un mot de passe pour un usage automatisé sécurisé.

---

## 🔐 Intégration Vault

Créer là clé API pour intéragir avec terraform depuis Vault


vault kv put iacrunner-outils/ovh_key \
    OVH_APPLICATION_KEY="ton_app_key" \
    OVH_APPLICATION_SECRET="ton_app_secret" \
    OVH_CONSUMER_KEY="ton_consumer_key" \
    description="API Keys for OVH storage"


Les secrets sont automatiquement générés puis stockés dans HashiCorp Vault (mount `iacrunner-outils`) :

| Secret Path | Champs | Description |
|---|---|---|
| `iacrunner-outils/aws_key` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Credentials S3 (Générés) |
| `iacrunner-outils/openstack_key` | `OS_AUTH_URL`, `OS_REGION_NAME`, `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET` | Credentials OpenStack (Générés) |

> ⚠️ Aucun secret n'est stocké en clair dans le repository.

---

## 🪣 Stockage S3 (OVH Object Storage)

Deux usages principaux :

1. **Backend Terraform**
   - Bucket : `infra-outils-sto-object-tf01`
   - Région : `EU-WEST-PAR` (Paris 3-AZ)
   - Endpoint : `https://s3.eu-west-par.io.cloud.ovh.net/`

2. **Bucket applicatif**
   - Versioning activé
   - Chiffrement AES256
   - Policy S3 full access pour `svc-terraform-aws`

---

## 🚀 Procédure d'Initialisation (BOOTSTRAP)

Cette procédure suit un ordre strict en **6 étapes** pour résoudre la dépendance circulaire entre le stockage du state et les accès S3 nécessaires pour y écrire.

### Étape 1 — Création du Bucket de Backend

Le bucket doit exister avant que Terraform ne tente de l'utiliser comme backend.

```bash
cd terraform-bootstrap
terraform init
terraform apply -var-file="../storage.tfvars"
cd ..
```

> 👉 Cette étape crée le bucket qui va stocker le state Terraform.
> 👉 Sans ça, le backend ne fonctionnera pas.

---

### Étape 2 — Initialisation Locale du Projet Principal

On force Terraform à travailler en local le temps de générer les accès.

**IMPORTANT** : Le bloc `backend "s3"` dans `backend.tf` doit être **entièrement commenté** (`/* ... */`).

```bash
terraform init -reconfigure
```

---

### Étape 3 — Importation du Bucket dans le State

On informe Terraform que le bucket créé à l'étape 1 est désormais géré par le module principal.

```bash
terraform import -var-file="storage.tfvars" \
  module.all_in_one_storage.ovh_cloud_project_storage.this \
  <SERVICE_NAME>/EU-WEST-PAR/<BUCKET_NAME>
```

> Le format d'importation est : `SERVICE_NAME/REGION/BUCKET_NAME`

---

### Étape 4 — Premier Apply (Génération des Secrets S3)

**NOTE** : Dans `modules/storage/main.tf`, les blocs suivants doivent être **commentés** car les identifiants OpenStack n'existent pas encore :
- `provider "openstack"`
- `resource "ovh_cloud_project_user" "os_user"`
- `resource "openstack_identity_application_credential_v3" "os_app_cred"`
- `resource "vault_generic_secret" "openstack_key"`
- Le provider `openstack` dans le bloc `required_providers`

```bash
terraform apply -var-file="storage.tfvars"
```

> 👉 Cette étape crée l'utilisateur S3, les credentials et pousse les clés dans Vault : `iacrunner-outils/aws_key`.

---

### Étape 5 — Migration vers le Backend Distant

1. Charger les credentials S3 depuis Vault :

```bash
export AWS_ACCESS_KEY_ID=$(vault kv get -mount="iacrunner-outils" -field=AWS_ACCESS_KEY_ID aws_key)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -mount="iacrunner-outils" -field=AWS_SECRET_ACCESS_KEY aws_key)
```

2. **Décommenter** le bloc `backend "s3"` dans `backend.tf`.

3. Migrer le state :

```bash
terraform init -migrate-state
```

> Répondre **yes** pour transférer le fichier local vers le bucket S3.

---

### Étape 6 — Finalisation OpenStack

**Décommenter** toutes les ressources OpenStack dans `modules/storage/main.tf` et lancer l'apply final :

```bash
terraform init
terraform apply -var-file="storage.tfvars"
```

> 👉 Cette étape crée l'utilisateur OpenStack, l'Application Credential et pousse les clés dans Vault : `iacrunner-outils/openstack_key`.

---

## 🔧 Variables

`storage.tfvars` :

```hcl
service_name      = "51b48fc072e34415922eb448c8121677"
bucket_prod_paris = "infra-outils-sto-object-tf01"
region_name       = "EU-WEST-PAR"
```

---

## 🔐 Pré-requis

1. **Vault accessible** :
```bash
export VAULT_ADDR=https://vault.xxx
```

2. **Secret OVH présent** :
```
path : iacrunner-outils/ovh_key
```

3. **Permissions Vault** :
   - Lecture : `iacrunner-outils/ovh_key`
   - Écriture : `iacrunner-outils/aws_key`, `iacrunner-outils/openstack_key`

4. **Région `EU-WEST-PAR` activée** dans le projet Public Cloud OVH :
   - Manager OVH → Public Cloud → Projet → Project Settings → Régions → Ajouter `EU-WEST-PAR`

---

## 🧪 Vérifications post-déploiement

```bash
# Vérifier les secrets Vault
vault kv get -mount="iacrunner-outils" aws_key
vault kv get -mount="iacrunner-outils" openstack_key

# Vérifier l'accès S3
export AWS_ACCESS_KEY_ID=$(vault kv get -mount="iacrunner-outils" -field=AWS_ACCESS_KEY_ID aws_key)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -mount="iacrunner-outils" -field=AWS_SECRET_ACCESS_KEY aws_key)
aws s3 ls --endpoint-url https://s3.eu-west-par.io.cloud.ovh.net/ s3://infra-outils-sto-object-tf01/

# Vérifier le state Terraform
terraform state list
```

---

## 🛡️ Sécurité

- Backend distant (pas de state local)
- Credentials dynamiques
- Secrets stockés uniquement dans Vault
- Séparation des rôles (S3 vs OpenStack)
- `prevent_destroy` activé sur le bucket backend

---

## ⚠️ Points d'attention

| Sujet | Détail |
|---|---|
| **Région** | La région pour le stockage S3 chez OVH est `EU-WEST-PAR` (majuscules pour l'API OVH, minuscules `eu-west-par` pour les endpoints S3) |
| **Format d'import** | `SERVICE_NAME/REGION/BUCKET_NAME` |
| **Bootstrap** | Toujours exécuter `terraform-bootstrap` en premier |
| **Bucket backend** | Ne jamais supprimer le bucket de backend sans avoir migré le state en local (`terraform init -reconfigure` avec backend commenté) |
| **Vault** | Vérifier les accès Vault avant exécution |
| **Connectivité** | Vérifier la connectivité vers `https://s3.eu-west-par.io.cloud.ovh.net/` |

---

## 🔄 Améliorations possibles

- Rotation automatique des credentials
- Ajout de lifecycle policies S3
- Multi-environnements (dev / prod)
- Intégration CI/CD (GitLab / GitHub Actions)

---

## 👨‍💻 Auteur

Infrastructure Terraform OVHcloud – Projet d'industrialisation du provisioning et de la gestion des accès.
