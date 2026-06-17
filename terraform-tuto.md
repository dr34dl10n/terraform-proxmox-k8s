# 📚 Tutorial Terraform - Guide de Base

Ce document présente les concepts de base de Terraform pour gérer vos infrastructures.

---

## 🚀 1. Installation

```bash
# Via Homebrew (macOS)
brew install terraform

# Via Chocolatey (Windows)
choco install terraform

# Via Snap (Linux)
snap install terraform
```

---

## 💻 2. Structure de l'architecture

```
📁 mon-projet-terraform
├── 📄 main.tf          # Configuration principale des ressources
├── 📄 variables.tf     # Variables pour réutiliser la configuration
├── 📄 outputs.tf       # Valeurs de sortie pour utiliser après apply
├── 📁 outputs          # Stockage des fichiers de sortie
└── 📄 terraform.tfstate # État (stocke l'infrastructure actuelle)
```

---

## 3. Les 3 Blocs essentiels

### Main.tf
```hcl
# Bloc de provider (ex: AWS, Docker)
provider "aws" {
  region = "eu-west-1"
}

# Bloc de ressource (crée les objets)
resource "aws_instance" "web_server" {
  ami           = "ami-0c7217cd317cfec"
  instance_type = "t3.micro"
  tags = {
    Name = "exemple-instance"
  }
}

# Bloc de data (consulte des infos existantes)
data "aws_ami" "example" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

---

## 4. Variables (variables.tf)
```hcl
# Variable avec valeur par défaut
variable "region" {
  description = "La région AWS"
  type        = string
  default     = "eu-west-1"
}

variable "instance_count" {
  description = "Nombre d'instances"
  type        = number
  default     = 2
}
```

---

## 5. Outputs (outputs.tf)
```hcl
# Affiche la valeur de la ressource après apply
output "instance_ip" {
  value = aws_instance.web_server.public_ip
  description = "L'adresse IP publique de l'instance"
}
```

---

## 6. Commandes de base

```bash
# Initialiser (installer les plugins)
terraform init

# Créer ou mettre à jour l'infrastructure
terraform apply

# Détruire l'infrastructure
terraform destroy

# Formatage du code
terraform fmt

# Planifier ce qui va être fait
terraform plan

# Lancer avec confirmation automatique
terraform apply -auto-approve

# Voir l'état actuel
terraform show

# Mettre à jour l'état manuellement
terraform state mv OLD_PATH NEW_PATH
```

---

## 7. Les différents types de ressources

### 💾 AWS
```hcl
resource "aws_instance" "web" { }          # Instance EC2
resource "aws_s3_bucket" "mybucket" { }    # S3 Bucket
resource "aws_vpc" "main" { }              # Réseau VPC
resource "aws_lb" "my_load_balancer" { }   # Load Balancer
```

### 🐳 Docker
```hcl
resource "docker_container" "nginx" {
  image = "nginx:latest"
  name  = "my_nginx"
}
```

### 🔐 Google Cloud
```hcl
resource "google_compute_instance" "vm" { }
resource "google_storage_bucket" "bucket" { }
```

---

## 8. Gestion des états (State Management)

```bash
# Sauvegarder l'état
terraform state pull > backup.tfstate

# Restaurer depuis un backup
terraform state push backup.tfstate

# Liste des ressources dans l'état
terraform state list

# Effacer une ressource de l'état
terraform state rm aws_instance.web_server
```

---

## 9. Travailler en équipe (State locking)

Pour éviter les conflits quand plusieurs personnes travaillent :

```bash
# Avec AWS S3 comme backend
terraform init -backend-config="bucket=my-terraform-state"

# Avec DB (PostgreSQL)
terraform init -backend-config="address=postgresql://user:pass@host/db"
```

---

## 10. Bonnes pratiques

✅ **Faire** :
- Garder `.tfstate` hors de version (gitignore)
- Utiliser des modules pour réutiliser la config
- Documenter chaque variable/output
- Utiliser `terraform fmt` pour formater
- Vérifier avec `terraform plan`

❌ **Éviter** :
- Ne pas toucher `terraform.tfstate`
- Ne pas créer la même ressource avec deux ID différents
- Ne pas faire push de l'état sur Git

---

## 11. Exemple complet minimal

**main.tf** :
```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  tags = {
    Name = "mon-premier-vpc"
  }
}
```

**Exécution** :
```bash
terraform init
terraform apply -auto-approve
terraform destroy -auto-approve
```

---

## 📖 Ressources utiles

- 🌐 [Documentation officielle](https://www.terraform.io/docs)
- 📚 [HCL Reference](https://www.terraform.io/docs/configuration/syntax.html)
- 🎓 [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

**Dernière mise à jour** : Aujourd'hui