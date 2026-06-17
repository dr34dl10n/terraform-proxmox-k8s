# 📝 Notes — Lab K8s Proxmox / Terraform

---

## 🔷 Bases de Terraform (rappel rapide)

### Cycle de vie Terraform

```
terraform init      →  Initialise le backend, télécharge les providers
terraform plan      →  Prévisualise les changements (dry-run)
terraform apply     →  Applique les changements (crée/modifie/détruit)
terraform destroy   →  Détruit toutes les ressources du state
```

### Concepts clés

| Concept | Rôle | Exemple |
|---|---|---|
| **Provider** | Plugin qui parle à une API | `bpg/proxmox` |
| **Resource** | Un élément infrastructurel à créer | `proxmox_virtual_environment_vm` |
| **Data source** | Lit une ressource existante (lecture seule) | `data "local_file"` |
| **Variable** | Paramètre d'entrée (type, défaut, description) | `variable "vm_cores" { default = 2 }` |
| **Output** | Valeur de sortie après le apply | `output "cp_ip" { value = var.cp_ip }` |
| **State** | Mapping entre config TF et réalité infra | Ne pas éditer manuellement ! |
| **Module** | Dossier réutilisable de ressources | Organise en packages |

### Fichiers principaux

| Fichier | Usage |
|---|---|
| `providers.tf` | Déclaration du provider + version |
| `variables.tf` | Déclarations de variables |
| `main.tf` | Ressources principales |
| `outputs.tf` | Valeurs de sortie |
| `terraform.tfvars` | Valeurs concrètes des variables (≠ commit !) |
| `.env` | Secrets via `TF_VAR_*` (≠ commit !) |

### Variables : déclaration vs affectation

```hcl
# variables.tf — déclaration
variable "proxmox_api_url" {
  type        = string
  description = "URL de l'API Proxmox"
}

# terraform.tfvars — affectation
proxmox_api_url = "https://192.168.1.2:8006"

# .env — secrets
export TF_VAR_proxmox_api_token="root@pam!terraform=secret"
```

Priorité (du + fort au - fort) :
1. `-var` en CLI
2. `-var-file` en CLI
3. `terraform.tfvars`
4. `*.auto.tfvars`
5. `TF_VAR_<name>` (variables d'environnement)
6. Valeurs par défaut dans `variables.tf`

### Blocs essentiels

```hcl
# Bloc terraform
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70"
    }
  }
}

# Bloc lifecycle (dans une resource)
lifecycle {
  create_before_destroy = true
  prevent_destroy       = false
  ignore_changes        = [initialization]
}

# count — créer N ressources identiques
resource "proxmox_virtual_environment_vm" "worker" {
  count = 2
  name  = "k8s-w${count.index + 1}"
}

# for_each — créer des ressources depuis une map
resource "proxmox_virtual_environment_vm" "worker" {
  for_each = { w1 = "192.168.1.232", w2 = "192.168.1.233" }
  name     = "k8s-${each.key}"
}
```

### Commandes utiles

```bash
terraform fmt          # Formate les fichiers .tf
terraform validate     # Valide la syntaxe
terraform output       # Affiche les outputs
terraform state list   # Liste les ressources dans le state
terraform show         # Affiche le state complet
terraform import      # Importe une ressource existante
terraform taint       # Force la recréation d'une ressource
```

---

## 🔷 Paramètres du Cluster K8s — Lab Proxmox

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Proxmox VE (pve)                      │
│                   4 vCPU / 16 Go RAM                    │
│                                                         │
│  vmbr0 : 192.168.1.2/24 (LAN)                          │
│        (VMs sur le même LAN, pas de NAT nécessaire)      │
│                                                         │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐          │
│  │  k8s-cp   │  │  k8s-w1   │  │  k8s-w2   │          │
│  │  (CP)     │  │  (Worker) │  │  (Worker) │          │
│  │  2 vCPU   │  │  1 vCPU   │  │  1 vCPU   │          │
│  │  4 Go RAM  │  │  2 Go RAM │  │  2 Go RAM │          │
│  │  20 Go SSD │  │  20 Go SSD│  │  20 Go SSD│          │
│  │ 192.168.1.231│  │ 192.168.1.232│ │ 192.168.1.233│         │
│  └───────────┘  └───────────┘  └───────────┘          │
│         └──────────────┼──────────────┘                │
│            vmbr0 (192.168.1.0/24 — LAN)              │
│            Accès direct LAN → internet                │
└─────────────────────────────────────────────────────────┘
```

### Variables Terraform (terraform.tfvars)

| Variable | Valeur | Description |
|---|---|---|
| `proxmox_api_url` | `https://192.168.1.2:8006` | URL API Proxmox |
| `proxmox_user` | `root@pam` | Utilisateur API |
| `proxmox_api_token` | *(via .env `TF_VAR_proxmox_api_token`)* | Token API |
| `cluster_name` | `k8s` | Préfixe noms de VMs |
| `proxmox_node` | `pve` | Nœud Proxmox |
| `template_vm_id` | `9000` | ID du template cloud-init |
| `vm_bridge` | `vmbr0` | Bridge réseau |
| `vm_network_cidr` | `192.168.1.0/24` | Sous-réseau VMs (LAN) |
| `vm_gateway` | `192.168.1.1` | Passerelle (routeur du LAN) |
| `vm_dns_servers` | `1.1.1.1, 1.0.0.1` | DNS |
| `control_plane_ip` | `192.168.1.231` | IP fixe CP |
| `worker_ips` | `192.168.1.232, .233` | IPs fixes Workers |
| `control_plane_cores` | `2` | vCPU CP |
| `control_plane_memory` | `4096` | RAM CP (Mo) |
| `worker_cores` | `1` | vCPU Workers |
| `worker_memory` | `2048` | RAM Workers (Mo) |
| `vm_disk_size` | `20` | Disque (Go, thin provisionné) |
| `vm_disk_storage` | `local-lvm` | Storage disques |
| `snippets_storage` | `local` | Storage snippets cloud-init |
| `ssh_public_key` | *(à définir)* | Clé SSH publique |
| `ssh_user` | `ubuntu` | Utilisateur SSH |

### Paramètres Kubernetes

| Paramètre | Valeur |
|---|---|
| **Version K8s** | v1.31 |
| **CRI** | containerd (SystemdCgroup = true) |
| **Cgroup driver** | systemd |
| **CNI** | Calico v3.27 |
| **Pod CIDR** | 10.244.0.0/16 (overlay K8s, pas le LAN) |
| **Service CIDR** | 10.96.0.0/12 |
| **Pause image** | registry.k8s.io/pause:3.9 |
| **Bootstrap** | kubeadm init + join |

### Ressources VM

| VM | vm_id | vCPU | RAM | Disk | IP | Rôle |
|---|---|---|---|---|---|---|
| k8s-cp | 101 | 2 | 4 096 Mo | 20 Go | 192.168.1.231 | Control Plane |
| k8s-w1 | 102 | 1 | 2 048 Mo | 20 Go | 192.168.1.232 | Worker |
| k8s-w2 | 103 | 1 | 2 048 Mo | 20 Go | 192.168.1.233 | Worker |

### Réseau

```
Internet ←→ 192.168.1.x (LAN)
                ↑
            Proxmox (pve)
            192.168.1.2/24
                ↑
    ┌──────────┼──────────┐
  k8s-cp    k8s-w1    k8s-w2
  .231       .232       .233
```

### Workflow de déploiement

```
1. source .env                                    # Charger les secrets
2. cp terraform.tfvars.example terraform.tfvars  # Configurer
3. cd terraform && terraform init                 # Init
4. terraform plan && terraform apply              # Provisionner
5. ssh ubuntu@192.168.1.231 "cloud-init status --wait"  # Attendre
6. ./scripts/init-control-plane.sh                # Init K8s
7. ./scripts/join-workers.sh                      # Join workers
8. ./scripts/copy-kubeconfig.sh                   # Kubeconfig local
9. kubectl get nodes                              # ✅
```

---

## ✅ Corrections appliquées

1. ✅ `proxmox_vm_qemu` → `proxmox_virtual_environment_vm` (API native bpg)
2. ✅ `template` → `clone { vm_id = ... }`
3. ✅ Cloud-init snippets uploadés via `proxmox_virtual_environment_file` + `user_data_file_id`
4. ✅ Fichier `terraform/info` supprimé → `.env` avec `TF_VAR_*`
5. ✅ `terraform.tfvars` exclu du git via `.gitignore`
6. ✅ IPs sur le LAN : `192.168.1.231/.232/.233` (pas de NAT nécessaire)
7. ✅ Specs VM ajustées aux ressources du Proxmox (4 vCPU / 16 Go RAM)
8. ✅ Anciens fichiers cloud-init (common.yaml, etc.) remplacés par les versions combinées