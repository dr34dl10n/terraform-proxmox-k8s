# =============================================================
# Providers — Déclaration du provider Proxmox (bpg)
# Utilise l'API native Proxmox VE (pas l'ancienne API QEMU)
# =============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70"
    }
  }

  # ⚠️  Local state only — pas de backend distant configuré.
  #     Pour un lab multi-utilisateur, ajouter un backend S3/Consul/etc. :
  #     backend "s3" {
  #       bucket = "terraform-state"
  #       key    = "proxmox-k8s-lab/terraform.tfstate"
  #       region = "us-east-1"
  #     }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url

  # Authentification par API Token (recommandé)
  api_token = var.proxmox_api_token

  # Désactiver la vérification TLS (cert auto-signé Proxmox)
  insecure = true

  # SSH pour les opérations nécessitant un accès shell
  # (upload de snippets, etc.)
  # ⚠️  Nécessite un SSH agent actif avec la clé du nœud Proxmox chargée
  #     ou définir PROXMOX_VE_SSH_PASSWORD / private_key
  ssh {
    agent    = true
    username = "root"

    # Déclaration explicite du nœud SSH (évite la résolution auto via l'API)
    node {
      name    = var.proxmox_node
      address = regex("https?://([^:]+)", var.proxmox_api_url)[0]
    }
  }
}