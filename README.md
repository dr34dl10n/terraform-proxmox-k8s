# 🏗️ Lab Kubernetes sur Proxmox via Terraform

> Provisionnement automatique d'un cluster K8s de test : **1 Control Plane + 2 Workers**  
> sur Proxmox VE avec Terraform + Cloud-Init + kubeadm

---

## 📋 Architecture Cible

```
┌─────────────────────────────────────────────────┐
│              Proxmox VE Host                     │
│                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐│
│  │  k8s-cp      │  │  k8s-w1      │  │ k8s-w2   ││
│  │  (Control    │  │  (Worker)    │  │ (Worker)  ││
│  │   Plane)     │  │              │  │          ││
│  │  4 vCPU      │  │  2 vCPU      │  │ 2 vCPU   ││
│  │  4 Go RAM    │  │  4 Go RAM    │  │ 4 Go RAM  ││
│  │  30 Go disk  │  │  30 Go disk  │  │ 30 Go dk ││
│  │  192.168.1.231│  │  192.168.1.232│  │192.168.1.233│
│  └──────────────┘  └──────────────┘  └──────────┘│
│          │                │               │      │
│          └────────────────┼───────────────┘      │
│                  vmbr0 (bridge)                    │
└─────────────────────────────────────────────────┘
```

---

## 📑 Table des matières

1. [Prérequis](#-prérequis)
2. [Arborescence du projet](#-arborescence-du-projet)
3. [Préparation Proxmox](#-préparation-proxmox)
4. [Configuration Terraform](#-configuration-terraform)
5. [Cloud-Init (préparation des nœuds)](#-cloud-init-préparation-des-nœuds)
6. [Déploiement](#-déploiement)
7. [Initialisation du cluster (kubeadm)](#-initialisation-du-cluster-kubeadm)
8. [Joindre les Workers](#-joindre-les-workers)
9. [Vérification](#-vérification)
10. [Post-install (CNI, Ingress, etc.)](#-post-install)
11. [Destruction du lab](#-destruction-du-lab)
12. [Troubleshooting](#-troubleshooting)

---

## 🔧 Prérequis

### Machine locale (from laquelle vous lancez Terraform)

| Outil | Version | Installation |
|-------|---------|-------------|
| **Terraform** | ≥ 1.5 | `brew install terraform` ou [terraform.io](https://developer.hashicorp.com/terraform/downloads) |
| **SSH client** | — | Normalement déjà présent |
| **kubectl** | ≥ 1.29 | `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"` |

### Côté Proxmox

| Prérequis | Détail |
|-----------|--------|
| **Proxmox VE** | ≥ 8.0 (testé sur 8.x) |
| **Template VM Cloud-Init** | Une VM template Ubuntu 22.04/24.04 avec cloud-init (voir section dédiée) |
| **API Token** | Un token Terraform avec droits `PVEVMAdmin` sur le noeud |
| **Bridge réseau** | `vmbr0` configuré (ou adapter dans les variables) |
| **Storage** | `local-lvm` ou équivalent pour les disques VM |

---

## 📁 Arborescence du projet

```
proxmox-k8s-lab/
├── README.md                        # ← vous êtes ici
├── terraform/
│   ├── main.tf                      # Ressources VM Proxmox
│   ├── variables.tf                  # Déclarations de variables
│   ├── outputs.tf                    # Sorties (IPs, commandes)
│   ├── providers.tf                 # Provider Proxmox
│   └── terraform.tfvars.example      # Exemple de fichier de vars
├── cloud-init/
│   ├── common.yaml                  # Préparation commune à tous les nœuds
│   ├── control-plane.yaml           # Spécifique au Control Plane
│   └── worker.yaml                  # Spécifique aux Workers
└── scripts/
    ├── init-control-plane.sh        # kubeadm init + Calico
    ├── join-workers.sh             # kubeadm join
    ├── copy-kubeconfig.sh           # Récupérer kubeconfig locally
    └── destroy-cluster.sh           # Nettoyage complet
```

---

## 🛠️ Préparation Proxmox

### 1. Créer un API Token pour Terraform

Depuis l'interface Proxmox Web UI :

1. **Datacenter → Permissions → API Tokens**
2. Cliquer **Add**
3. Sélectionner l'utilisateur `root@pam` (ou créer un utilisateur dédié)
4. Donner un ID : `terraform`
5. ⚠️ **Décocher "Privilege Separation"** si vous voulez que le token hérite des droits de l'utilisateur
6. **Copier le Secret** (il ne sera affiché qu'une seule fois !)

Ou en CLI :
```bash
pveum user token add root@pam terraform --privsep 0
```

### 2. Assigner les permissions

```bash
pveum acl modify / --users root@pam --roles PVEVMAdmin
# Ou pour un utilisateur dédié :
# pveum role add Terraform -privs "VM.Allocate VM.Console VM.Config.CDROM VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt SDN.Use Sys.Audit Sys.Console"
# pveum acl modify / --users terraform@pve --roles Terraform
```

### 3. Créer le template Cloud-Init Ubuntu

C'est l'étape la plus importante. Ce template sera cloné par Terraform pour chaque nœud.

```bash
# Sur le host Proxmox, en SSH :

# 1. Télécharger l'image Ubuntu Cloud (22.04 LTS recommandé)
cd /tmp
wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img

# 2. Installer libguestfs-tools pour自定义 l'image (optionnel mais recommandé)
apt install -y libguestfs-tools

# 3. Installer qemu-guest-agent dans l'image (nécessaire pour que Terraform attende l'IP)
virt-customize -a ubuntu-22.04-server-cloudimg-amd64.img \
  --install qemu-guest-agent

# 4. Créer la VM template
qm create 9000 --name "ubuntu-2204-cloudinit" --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --disk local-lvm:0,import-from=/tmp/ubuntu-22.04-server-cloudimg-amd64.img

# 5. Configurer cloud-init sur la VM
qm set 9000 --ciuser ubuntu
qm set 9000 --sshkeys ~/.ssh/authorized_keys    # votre clé SSH publique
qm set 9000 --agent enabled=1

# 6. Ajouter un CDROM pour cloud-init (nécessaire)
qm set 9000 --scsi2 local-lvm:cloudinit

# 7. Convertir en template
qm template 9000

echo "✅ Template VM 9000 prêt !"
```

> 💡 **Note :** Si vous préférez Ubuntu 24.04, remplacez `22.04` par `24.04` dans l'URL.

---

## ⚙️ Configuration Terraform

### providers.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  username  = var.proxmox_user
  password  = var.proxmox_password
  api_token = var.proxmox_api_token

  ssh {
    agent    = true
    username = "root"
  }
}
```

### variables.tf

```hcl
# --- Proxmox Connection ---
variable "proxmox_api_url" {
  description = "URL de l'API Proxmox (ex: https://192.168.1.10:8006)"
  type        = string
}

variable "proxmox_user" {
  description = "Utilisateur Proxmox (ex: root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Mot de passe Proxmox (si pas de token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_api_token" {
  description = "API Token Proxmox (format: user@realm!tokenid=secret)"
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
  default     = 9000
}

# --- Network ---
variable "vm_bridge" {
  description = "Bridge réseau Proxmox"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_cidr" {
  description = "Sous-réseau CIDR (ex: 192.168.1.0/24)"
  type        = string
  default     = "192.168.1.0/24"
}

variable "vm_gateway" {
  description = "Passerelle par défaut"
  type        = string
  default     = "192.168.1.1"
}

variable "vm_dns_servers" {
  description = "Serveurs DNS"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
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
  type    = number
  default = 4
}

variable "control_plane_memory" {
  type    = number
  default = 4096
}

variable "worker_cores" {
  type    = number
  default = 2
}

variable "worker_memory" {
  type    = number
  default = 4096
}

variable "vm_disk_size" {
  description = "Taille disque en Go"
  type        = number
  default     = 30
}

variable "vm_disk_storage" {
  description = "Storage Proxmox pour les disques"
  type        = string
  default     = "local-lvm"
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
```

### main.tf

```hcl
# --- DATA : lire le contenu des fichiers cloud-init ---
data "local_file" "common_cloudinit" {
  filename = "${path.module}/../cloud-init/common.yaml"
}

data "local_file" "cp_cloudinit" {
  filename = "${path.module}/../cloud-init/control-plane.yaml"
}

data "local_file" "worker_cloudinit" {
  filename = "${path.module}/../cloud-init/worker.yaml"
}

# --- Ressource : Control Plane ---
resource "proxmox_vm_qemu" "control_plane" {
  count      = 1
  vm_id      = 101
  name       = "${var.cluster_name}-cp"
  desc       = "Kubernetes Control Plane Node"
  node       = var.proxmox_node
  template   = var.template_vm_id

  # Hardware
  cores   = var.control_plane_cores
  sockets = 1
  memory  = var.control_plane_memory

  # Disk
  disk {
    storage = var.vm_disk_storage
    type    = "scsi"
    size    = "${var.vm_disk_size}G"
  }

  # Network
  network {
    bridge = var.vm_bridge
    model = "virtio"
  }

  # Cloud-Init
  ciuser       = var.ssh_user
  cipassword   = ""  # On utilise les clés SSH
  sshkeys      = var.ssh_public_key

  # IP statique
  ipconfig0 = "ip=${var.control_plane_ip}/24,gw=${var.vm_gateway}"

  # Cloud-init personnalisé (snippets)
  cloudinit_disk = "scsi2"

  # QEMU Agent (pour récupérer l'IP)
  agent = 1

  # Démarrage automatique
  onboot  = true
  startup = "order=1"

  # Ignorer les changements de cloud-init après le premier apply
  lifecycle {
    ignore_changes = [
      cloudinit_disk,
      ciuser,
      cipassword,
      sshkeys,
      ipconfig0,
    ]
  }
}

# --- Ressource : Workers ---
resource "proxmox_vm_qemu" "worker" {
  count      = 2
  vm_id      = 102 + count.index
  name       = "${var.cluster_name}-w${count.index + 1}"
  desc       = "Kubernetes Worker Node ${count.index + 1}"
  node       = var.proxmox_node
  template   = var.template_vm_id

  # Hardware
  cores   = var.worker_cores
  sockets = 1
  memory  = var.worker_memory

  # Disk
  disk {
    storage = var.vm_disk_storage
    type    = "scsi"
    size    = "${var.vm_disk_size}G"
  }

  # Network
  network {
    bridge = var.vm_bridge
    model = "virtio"
  }

  # Cloud-Init
  ciuser       = var.ssh_user
  cipassword   = ""
  sshkeys      = var.ssh_public_key

  # IP statique
  ipconfig0 = "ip=${var.worker_ips[count.index]}/24,gw=${var.vm_gateway}"

  # QEMU Agent
  agent = 1

  # Démarrage automatique
  onboot  = true
  startup = "order=2"

  lifecycle {
    ignore_changes = [
      cloudinit_disk,
      ciuser,
      cipassword,
      sshkeys,
      ipconfig0,
    ]
  }
}
```

### outputs.tf

```hcl
output "control_plane_ip" {
  value       = var.control_plane_ip
  description = "IP du nœud Control Plane"
}

output "worker_ips" {
  value       = var.worker_ips
  description = "IPs des nœuds Workers"
}

output "ssh_command_cp" {
  value       = "ssh ${var.ssh_user}@${var.control_plane_ip}"
  description = "Commande SSH pour le Control Plane"
}

output "ssh_command_w1" {
  value       = "ssh ${var.ssh_user}@${var.worker_ips[0]}"
  description = "Commande SSH pour le Worker 1"
}

output "ssh_command_w2" {
  value       = "ssh ${var.ssh_user}@${var.worker_ips[1]}"
  description = "Commande SSH pour le Worker 2"
}

output "kubeadm_init_hint" {
  value       = "Exécutez : ./scripts/init-control-plane.sh ${var.control_plane_ip}"
  description = "Commande pour initialiser le cluster"
}
```

### terraform.tfvars.example

```hcl
# --- Copiez ce fichier en terraform.tfvars et remplissez les valeurs ---

# Connexion Proxmox
proxmox_api_url    = "https://192.168.1.10:8006"
proxmox_user       = "root@pam"
proxmox_password   = ""                                   # Optionnel si token
proxmox_api_token  = "root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Cluster
cluster_name       = "k8s"
proxmox_node       = "pve"                                 # Nom du noeud Proxmox
template_vm_id     = 9000

# Réseau — adaptez à votre lan
vm_network_cidr    = "192.168.1.0/24"
vm_gateway         = "192.168.1.1"
control_plane_ip   = "192.168.1.231"
worker_ips         = ["192.168.1.232", "192.168.1.233"]

# Matériel
control_plane_cores  = 4
control_plane_memory = 4096
worker_cores         = 2
worker_memory        = 4096
vm_disk_size         = 30
vm_disk_storage      = "local-lvm"

# SSH — collez votre clé publique
ssh_public_key      = "ssh-ed25519 AAAA... votre@machine"
ssh_user            = "ubuntu"
```

---

## 🌥️ Cloud-Init (préparation des nœuds)

Ces fichiers sont exécutés au premier boot de chaque VM et préparent le système pour Kubernetes.

### common.yaml — Préparation commune (tous les nœuds)

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - conntrack
  - socat
  - ebtables
  - ethtool
  - nfs-common
  - ceph-common
  - glusterfs-client
  - jq

write_files:
  # --- Kernel modules pour Kubernetes ---
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # --- Sysctl pour Kubernetes ---
  - path: /etc/sysctl.d/99-kubernetes.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

  # --- Configuration containerd ---
  - path: /etc/containerd/config.toml
    content: |
      version = 2
      [plugins]
        [plugins."io.containerd.grpc.v1.cri"]
          sandbox_image = "registry.k8s.io/pause:3.9"
          [plugins."io.containerd.grpc.v1.cri".containerd]
            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
              [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
                runtime_type = "io.containerd.runc.v2"
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
                  SystemdCgroup = true

  # --- crictl config ---
  - path: /etc/crictl.yaml
    content: |
      runtime-endpoint: unix:///run/containerd/containerd.sock
      image-endpoint: unix:///run/containerd/containerd.sock
      timeout: 10
      debug: false

runcmd:
  # --- Charger les modules kernel immédiatement ---
  - modprobe overlay
  - modprobe br_netfilter

  # --- Appliquer les sysctl ---
  - sysctl --system

  # --- Désactiver le swap (requis par Kubernetes) ---
  - swapoff -a
  - sed -i '/swap/d' /etc/fstab

  # --- Installer containerd ---
  - apt-get install -y containerd

  # --- Redémarrer containerd avec la config k8s ---
  - systemctl restart containerd
  - systemctl enable containerd

  # --- Ajouter le dépôt Kubernetes ---
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

  # --- Installer kubeadm, kubelet, kubectl ---
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable kubelet

  # --- Vérification ---
  - echo "✅ Node ready for kubeadm init/join"
```

### control-plane.yaml — Spécifique au Control Plane

```yaml
#cloud-config
write_files:
  # --- kubeadm config pour init ---
  - path: /etc/kubeadm/kubeadm-config.yaml
    owner: root:root
    permissions: '0644'
    content: |
      apiVersion: kubeadm.k8s.io/v1beta3
      kind: InitConfiguration
      nodeRegistration:
        criSocket: unix:///run/containerd/containerd.sock
        kubeletExtraArgs:
          cgroup-driver: "systemd"
      ---
      apiVersion: kubeadm.k8s.io/v1beta3
      kind: ClusterConfiguration
      kubernetesVersion: "v1.31"
      controlPlaneEndpoint: "CP_IP_REPLACE:6443"
      networking:
        podSubnet: "10.244.0.0/16"
        serviceSubnet: "10.96.0.0/12"
      ---
      apiVersion: kubelet.config.k8s.io/v1beta1
      kind: KubeletConfiguration
      cgroupDriver: "systemd"

runcmd:
  - echo "✅ Control Plane cloud-init complete. Run kubeadm init manually."
```

> ⚠️ `CP_IP_REPLACE` sera remplacé dynamiquement par le script `init-control-plane.sh`.

### worker.yaml — Spécifique aux Workers

```yaml
#cloud-config
runcmd:
  - echo "✅ Worker cloud-init complete. Run kubeadm join after CP init."
```

---

## 🚀 Déploiement

### 1. Configurer les variables

```bash
cd /data/CKA/proxmox-k8s-lab/terraform

# Copier et éditer le fichier de variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

### 2. Premier apply Terraform

```bash
terraform init
terraform plan
terraform apply
```

⏱ Le provisioning prend ~2-3 minutes. Les VMs bootent et exécutent le cloud-init (installation des paquets, config containerd, etc.) — **comptez ~5-10 min** pour que cloud-init termine sur chaque nœud.

### 3. Vérifier que les VMs sont prêtes

```bash
# Les IPs sont dans les outputs Terraform
terraform output

# SSH vers le Control Plane et vérifier que cloud-init a fini
ssh ubuntu@192.168.1.231 "cloud-init status --wait"
# → "status: done"

# Vérifier que kubeadm est installé
ssh ubuntu@192.168.1.231 "kubeadm version"
```

> 💡 Si `cloud-init status` reste en `running`, attendez. Vous pouvez surveiller avec :
> ```bash
> ssh ubuntu@192.168.1.231 "tail -f /var/log/cloud-init-output.log"
> ```

---

## 🏗️ Initialisation du cluster (kubeadm)

Une fois les VMs prêtes, lancez le script d'initialisation :

```bash
cd /data/CKA/proxmox-k8s-lab
./scripts/init-control-plane.sh
```

Ce script :
1. Initialise le cluster avec `kubeadm init`
2. Installe le CNI **Calico** (ou Weave, configurable)
3. Copie le kubeconfig pour l'utilisateur `ubuntu`
4. Affiche la commande `kubeadm join` pour les workers

### Mode manuel (si vous préférez)

```bash
# Sur le Control Plane (SSH)
ssh ubuntu@192.168.1.231

sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.1.231 \
  --kubernetes-version=v1.31

# Configurer kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installer le CNI Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml
```

---

## 🔗 Joindre les Workers

Après l'initialisation du Control Plane, utilisez le script :

```bash
./scripts/join-workers.sh
```

Ou manuellement :

```bash
# Sur le Control Plane, récupérer le token
ssh ubuntu@192.168.1.231 "kubeadm token create --print-join-command"

# Sur chaque Worker, exécuter la commande affichée
ssh ubuntu@192.168.1.232 "sudo kubeadm join 192.168.1.231:6443 --token xxxxx --discovery-token-ca-cert-hash sha256:xxxxx"
ssh ubuntu@192.168.1.233 "sudo kubeadm join 192.168.1.231:6443 --token xxxxx --discovery-token-ca-cert-hash sha256:xxxxx"
```

---

## ✅ Vérification

```bash
# Depuis le Control Plane ou votre machine locale avec kubeconfig
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# k8s-cp   Ready    control-plane   5m    v1.31.x
# k8s-w1   Ready    <none>          2m    v1.31.x
# k8s-w2   Ready    <none>          2m    v1.31.x

# Vérifier les composants du control plane
kubectl get pods -n kube-system

# Vérifier le CNI
kubectl get pods -n calico-system
# ou kubectl get pods -n kube-system | grep calico

# Déployer un pod de test
kubectl run test-nginx --image=nginx --restart=Never
kubectl get pods -o wide   # Doit montrer une IP dans le CIDR pod
```

---

## 🎁 Post-install (optionnel)

### Ingress Controller (NGINX)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
```

### Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Si les certificats auto-signés posent problème :
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### Kubeadm : configurer le auto-completion

```bash
# Sur chaque nœud
echo 'source <(kubeadm completion bash)' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
alias k=kubectl
complete -o default -F __start_kubectl k
```

---

## 💣 Destruction du lab

```bash
cd /data/CKA/proxmox-k8s-lab

# Script complet (reset kubeadm + destroy TF)
./scripts/destroy-cluster.sh

# Ou Terraform uniquement
cd terraform
terraform destroy
```

---

## 🔍 Troubleshooting

| Problème | Solution |
|----------|----------|
| **VM stuck "waiting for IP"** | Vérifier que `qemu-guest-agent` est installé dans le template. Sur le nœud Proxmox : `qm agent <vmid> ping` |
| **`kubeadm init` échoue : swap actif** | `ssh ubuntu@IP "sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab"` |
| **`[ERROR Swap]: running with swap on is not supported`** | Même chose — le cloud-init devrait l'avoir fait, vérifiez qu'il a terminé |
| **Nodes `NotReady`** | Vérifier le CNI : `kubectl get pods -n kube-system -l k8s-app=calico-node`. Vérifier les logs : `kubectl logs -n kube-system <calico-pod>` |
| **CrashLoopBackOff kube-proxy** | Vérifier la config réseau : `kubectl logs -n kube-system <kube-proxy-pod>` |
| **`containerd` pas démarré** | `ssh ubuntu@IP "sudo systemctl restart containerd && sudo systemctl status containerd"` |
| **`kubeadm join` : token expiré** | Régénérer : `ssh ubuntu@CP_IP "kubeadm token create --print-join-command"` |
| **Cloud-init ne s'exécute pas** | Vérifier : `cat /var/log/cloud-init.log`. Reset : `sudo cloud-init clean && sudo reboot` |
| **Proxmox API inaccessible** | Vérifier l'URL, le token, et que l'API est bien sur le port 8006 avec HTTPS |
| **Terraform : `disk size` error** | Le disque du template doit être plus petit que la taille désirée. Sinon utiliser `resize_disk` |

### Reset complet d'un nœud (pour repartir de zéro)

```bash
# Sur le nœud à reset
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo ipvsadm --clear
```

---

## 📌 Résumé rapide (cheat sheet workflow)

```bash
# 1. Préparer
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars

# 2. Provisionner
cd terraform && terraform init && terraform apply -auto-approve

# 3. Attendre cloud-init (~5-10 min)
ssh ubuntu@CP_IP "cloud-init status --wait"

# 4. Initialiser le cluster
./scripts/init-control-plane.sh

# 5. Joindre les workers
./scripts/join-workers.sh

# 6. Récupérer kubeconfig localement
./scripts/copy-kubeconfig.sh

# 7. Vérifier
kubectl get nodes

# 🎯 C'est prêt ! Practicez pour la CKA !

# 💣 Pour tout détruire
./scripts/destroy-cluster.sh
```

---

> 🚀 **Tip CKA :** Montez et détruisez ce cluster régulièrement. C'est exactement le type de tâche testée à l'examen (kubeadm init/join, troubleshooting de nœuds NotReady, etc.). La répétition est la clé !