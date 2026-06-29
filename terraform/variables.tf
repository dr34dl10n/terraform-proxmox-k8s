# =============================================================
# Variables Terraform — Lab Kubernetes Proxmox
# =============================================================

# --- Proxmox Connection ---
variable "proxmox_api_url" {
  description = "URL de l'API Proxmox (ex: https://192.168.1.10:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "API Token Proxmox (format: user@realm!tokenid=secret) — fournir via TF_VAR_proxmox_api_token dans .env"
  type        = string
  sensitive   = true
}

# --- Cluster Config ---
variable "cluster_name" {
  description = "Nom du cluster (préfixe des VMs)"
  type        = string
  default     = "k8s"
}

variable "proxmox_node" {
  description = "Nom du nœud Proxmox où créer les VMs"
  type        = string
}

variable "template_vm_id" {
  description = "ID du template Cloud-Init (ex: 9000)"
  type        = number
  default     = 9001
}

# --- Kubernetes ---
# Version mineure (ex: "1.35") alignée sur celle utilisée lors de l'examen CKA
# (cf. curriculum CNCF : CKA_Curriculum_v<mineure>.pdf).
# Sert à : configurer le dépôt apt pkgs.k8s.io et le kubernetesVersion de kubeadm.
variable "kubernetes_version" {
  description = "Version Kubernetes (mineure, ex: 1.35) — alignée sur l'examen CKA"
  type        = string
  default     = "1.35"
}

# --- Network ---
variable "vm_bridge" {
  description = "Bridge réseau Proxmox"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_cidr" {
  description = "Sous-réseau CIDR du réseau VMs"
  type        = string
  default     = "192.168.1.0/24"
}

variable "vm_gateway" {
  description = "Passerelle par défaut (routeur du LAN)"
  type        = string
  default     = "192.168.1.1"
}

variable "vm_dns_servers" {
  description = "Serveurs DNS"
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}

variable "control_plane_ip" {
  description = "IP fixe du Control Plane"
  type        = string
  default     = "192.168.1.231"
}

variable "worker_ips" {
  description = "IPs fixes des Workers"
  type        = list(string)
  default     = ["192.168.1.232", "192.168.1.233"]
}

# --- VM Specs ---
variable "control_plane_cores" {
  description = "Nombre de vCPU pour le Control Plane"
  type        = number
  default     = 2
}

variable "control_plane_memory" {
  description = "Mémoire (Mo) pour le Control Plane"
  type        = number
  default     = 4096
}

variable "worker_cores" {
  description = "Nombre de vCPU pour chaque Worker"
  type        = number
  default     = 1
}

variable "worker_memory" {
  description = "Mémoire (Mo) pour chaque Worker"
  type        = number
  default     = 2048
}

variable "vm_disk_size" {
  description = "Taille disque en Go"
  type        = number
  default     = 20
}

variable "vm_disk_storage" {
  description = "Storage Proxmox pour les disques"
  type        = string
  default     = "local-lvm"
}

variable "snippets_storage" {
  description = "Storage Proxmox pour les snippets cloud-init (doit avoir content=snippets activé)"
  type        = string
  default     = "local"
}

# --- SSH ---
variable "ssh_public_key" {
  description = "Clé SSH publique à injecter dans les VMs"
  type        = string
}

variable "ssh_user" {
  description = "Utilisateur SSH (doit matcher le cloud-init du template)"
  type        = string
  default     = "ubuntu"
}
