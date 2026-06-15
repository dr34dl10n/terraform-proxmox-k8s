# Lab Kubernetes sur Proxmox via Terraform

<div align="center">

![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-326CE5?logo=kubernetes&logoColor=white)
![Proxmox VE](https://img.shields.io/badge/Proxmox_VE-≥8.0-E57000?logo=proxmox&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-≥1.5-7B42BC?logo=terraform&logoColor=white)
![Cloud‑Init](https://img.shields.io/badge/Cloud_Init-✓-18A4E0?logo=cloudinit&logoColor=white)
![kubeadm](https://img.shields.io/badge/kubeadm-✓-326CE5?logo=kubernetes&logoColor=white)
![Calico](https://img.shields.io/badge/Calico-3.28-F39221?logo=projectcalico&logoColor=white)
![containerd](https://img.shields.io/badge/containerd-✓-5F6368?logo=containerd&logoColor=white)
![CKA](https://img.shields.io/badge/CKA-Exam_Prep-00A19A?logo=kubernetes&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?logo=opensourceinitiative&logoColor=white)

</div>

> Provisionnement automatique d'un cluster K8s de test : **1 Control Plane + 2 Workers**
> sur Proxmox VE avec Terraform + Cloud-Init + kubeadm

---

## Architecture Cible

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

**Réseau :** Les VMs sont sur `192.168.1.0/24`, même LAN que le Proxmox.
Pas de NAT nécessaire — les VMs accèdent directement à internet via la gateway du LAN.
Le Pod CIDR K8s est `10.244.0.0/16` (pour éviter le chevauchement avec le LAN `192.168.1.x`).

---

## Table des matières

1. [Prérequis](#prérequis)
2. [Arborescence du projet](#arborescence-du-projet)
3. [Préparation Proxmox](#préparation-proxmox)
4. [Configuration Terraform](#configuration-terraform)
5. [Cloud-Init](#cloud-init-préparation-des-nœuds)
6. [Déploiement](#déploiement)
7. [Initialisation du cluster](#initialisation-du-cluster-kubeadm)
8. [Joindre les Workers](#joindre-les-workers)
9. [Vérification](#vérification)
10. [Destruction du lab](#destruction-du-lab)
11. [Troubleshooting](#troubleshooting)

---

## Prérequis

### Machine locale

| Outil | Version | Installation |
|-------|---------|-------------|
| **Terraform** | ≥ 1.5 | [terraform.io](https://developer.hashicorp.com/terraform/downloads) |
| **SSH client** | — | Déjà présent |
| **kubectl** | ≥ 1.29 | `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"` |

### Côté Proxmox

| Prérequis | Détail |
|-----------|--------|
| **Proxmox VE** | ≥ 8.0 (testé sur 9.1) |
| **Template VM Cloud-Init** | Ubuntu 22.04/24.04 avec cloud-init + qemu-guest-agent (ID 9001) |
| **API Token** | Token Terraform avec droits `PVEVMAdmin` |
| **Réseau LAN** | VMs en 192.168.1.231-233, pas de NAT |
| **Storage** | `local-lvm` pour les disques, `local` pour les snippets |

---

## Arborescence du projet

```
proxmox-k8s-lab/
├── README.md
├── NOTES.md                          # Rappel Terraform + paramètres cluster
├── .env                              # Secrets (TF_VAR_proxmox_api_token) — EXCLU du git
├── .gitignore
├── terraform/
│   ├── main.tf                       # Ressources VM Proxmox + upload snippets
│   ├── variables.tf                  # Déclarations de variables
│   ├── outputs.tf                    # Sorties (IPs, commandes SSH)
│   ├── providers.tf                  # Provider Proxmox (bpg >= 0.70)
│   └── terraform.tfvars.example      # Exemple de fichier de vars
├── cloud-init/
│   └── user-data.yaml.tpl            # Template unique cloud-init (CP + Workers)
└── scripts/
    ├── common.sh                    # Config partagée (terraform output + tfvars fallback)
    ├── init-control-plane.sh         # kubeadm init + Calico
    ├── join-workers.sh               # kubeadm join
    ├── copy-kubeconfig.sh            # Récupérer kubeconfig localement
    └── destroy-cluster.sh             # Nettoyage complet
```

---

## Préparation Proxmox

### 1. Créer un API Token pour Terraform

Depuis l'interface Proxmox Web UI :

1. **Datacenter → Permissions → API Tokens**
2. Cliquer **Add** → Utilisateur `root@pam`, ID `terraform`
3. **Décocher "Privilege Separation"**
4. Copier le Secret (affiché une seule fois !)

Ou en CLI :
```bash
pveum user token add root@pam terraform --privsep 0
```

Stocker le token dans `.env` :
```bash
export TF_VAR_proxmox_api_token="root@pam!tokenid=secret"
```

### 2. Assigner les permissions

```bash
pveum acl modify / --users root@pam --roles PVEVMAdmin
```

### 3. Configurer le réseau (bridge LAN)

Les VMs sont sur le même LAN (`192.168.1.0/24`) que le Proxmox via `vmbr0`.
Pas de configuration réseau supplémentaire nécessaire — le bridge est déjà en place.

Vérifier que `vmbr0` est bien connecté au réseau physique et que le forwarding IP est activé :

```bash
# Vérifier le forwarding
sysctl net.ipv4.ip_forward
# Si nécessaire :
sysctl -w net.ipv4.ip_forward=1
```

### 4. Activer les snippets sur le storage `local`

```bash
pvesm set local --content iso,vmtmpl,backup,snippets
```

Ou via Web UI : Datacenter → Storage → `local` → Edit → cocher **Snippets**.

Vérifier :
```bash
ls /var/lib/vz/snippets/
```

### 5. Créer le template Cloud-Init Ubuntu

```bash
cd /tmp
wget https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img

# Installer qemu-guest-agent dans l'image
apt install -y libguestfs-tools
virt-customize -a ubuntu-24.04-server-cloudimg-amd64.img --install qemu-guest-agent

# Créer la VM template
qm create 9001 \
  --name "ubuntu-2404-cloudinit" \
  --memory 2048 --cores 2 --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l24 \
  --agent 1 \
  --cpu host \
  --scsihw virtio-scsi-pci \
  --boot order=scsi0 \
  --serial0 socket --vga serial0

# Importer le disque
qm importdisk 9001 /tmp/ubuntu-24.04-server-cloudimg-amd64.img local-lvm --format qcow2

# Configurer le disque attaché
qm set 9001 --scsi0 local-lvm:vm-9001-disk-0
qm set 9001 --boot order=scsi0

# Configurer cloud-init
qm set 9001 --ciuser ubuntu
qm set 9001 --sshkeys ~/.ssh/authorized_keys
qm set 9001 --scsi2 local-lvm:cloudinit

# Convertir en template
qm template 9001
echo "Template VM 9001 prêt !"
```

---

## Configuration Terraform

### Variables principales

| Variable | Valeur | Description |
|---|---|---|
| `proxmox_api_url` | `https://192.168.1.2:8006` | URL API Proxmox |
| `proxmox_node` | `pve` | Nœud Proxmox |
| `cluster_name` | `k8s` | Préfixe noms de VMs |
| `vm_network_cidr` | `192.168.1.0/24` | Sous-réseau VMs (LAN) |
| `vm_gateway` | `192.168.1.1` | Gateway (routeur du LAN) |
| `control_plane_ip` | `192.168.1.231` | IP du Control Plane |
| `worker_ips` | `192.168.1.232, .13` | IPs des Workers |
| `control_plane_cores` | `2` | vCPU CP |
| `control_plane_memory` | `4096` | RAM CP (Mo) |
| `worker_cores` | `1` | vCPU Workers |
| `worker_memory` | `2048` | RAM Workers (Mo) |
| `vm_disk_size` | `20` | Disque (Go, thin provisionné) |

> Les secrets sont dans `.env` (fichier exclu du git).

### Ressources VM

| VM | vm_id | vCPU | RAM | Disk | IP | Rôle |
|---|---|---|---|---|---|---|
| k8s-cp | 101 | 2 | 4 096 Mo | 20 Go | 192.168.1.231 | Control Plane |
| k8s-w1 | 102 | 1 | 2 048 Mo | 20 Go | 192.168.1.232 | Worker |
| k8s-w2 | 103 | 1 | 2 048 Mo | 20 Go | 192.168.1.233 | Worker |

---

## Cloud-Init (préparation des nœuds)

Le template unique `cloud-init/user-data.yaml.tpl` est rendu via Terraform `templatefile()` 
et uploadé comme **snippet Proxmox** (`proxmox_virtual_environment_file`) puis injecté dans chaque VM via `user_data_file_id`.
Les parties CP-only (InitConfiguration) et Worker-only (JoinConfiguration) sont conditionnées par `is_control_plane`.

Contenu installé sur chaque nœud :
- Packages système (curl, jq, conntrack, etc.)
- Kernel modules (overlay, br_netfilter) + sysctl
- containerd configuré avec SystemdCgroup (config écrite **après** l'install)
- kubeadm / kubelet / kubectl v1.31
- Swap désactivé
- Bash-completion pour kubectl

Le Control Plane reçoit `/etc/kubeadm/kubeadm-config.yaml` avec `InitConfiguration` + `ClusterConfiguration`.
Les Workers reçoivent `/etc/kubeadm/kubeadm-config.yaml` avec `JoinConfiguration` (token rempli par le script `join-workers.sh`).

---

## Déploiement

### 1. Configurer les variables

```bash
cd proxmox-k8s-lab

# Charger les secrets
source .env

# Copier et éditer le fichier de vars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
```

### 2. Premier apply Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

⏱ Le provisioning prend ~2-3 minutes. Les VMs bootent et exécutent cloud-init
(packages, containerd, kubeadm) — **comptez ~5-10 min** pour que cloud-init termine.

### 3. Vérifier que les VMs sont prêtes

```bash
# IPs dans les outputs Terraform
terraform output

# Vérifier cloud-init sur le CP
ssh ubuntu@192.168.1.231 "cloud-init status --wait"
# → "status: done"

# Vérifier kubeadm
ssh ubuntu@192.168.1.231 "kubeadm version"
```

---

## Initialisation du cluster (kubeadm)

```bash
cd proxmox-k8s-lab
./scripts/init-control-plane.sh
```

Ce script :
1. Vérifie que cloud-init est terminé
2. Remplace `CP_IP_REPLACE` dans la config kubeadm
3. Lance `kubeadm init`
4. Installe le CNI **Calico**
5. Configure kubeconfig pour l'utilisateur `ubuntu`

### Mode manuel

```bash
ssh ubuntu@192.168.1.231

sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.1.231 \
  --kubernetes-version=v1.31

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml
```

---

## Joindre les Workers

```bash
./scripts/join-workers.sh
```

Ou manuellement :
```bash
ssh ubuntu@192.168.1.231 "kubeadm token create --print-join-command"
# Puis sur chaque worker :
ssh ubuntu@192.168.1.232 "sudo kubeadm join 192.168.1.231:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
ssh ubuntu@192.168.1.233 "sudo kubeadm join 192.168.1.231:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
```

---

## Vérification

```bash
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# k8s-cp   Ready    control-plane   5m    v1.31.x
# k8s-w1   Ready    <none>          2m    v1.31.x
# k8s-w2   Ready    <none>          2m    v1.31.x
```

Récupérer le kubeconfig localement :
```bash
./scripts/copy-kubeconfig.sh
```

---

## Destruction du lab

```bash
# Script complet (reset kubeadm + destroy TF)
./scripts/destroy-cluster.sh

# Ou Terraform uniquement
cd terraform && terraform destroy
```

---

## Troubleshooting

| Problème | Solution |
|----------|----------|
| **VM stuck "waiting for IP"** | Vérifier qemu-guest-agent dans le template : `qm agent <vmid> ping` |
| **`kubeadm init` échoue : swap actif** | `ssh ubuntu@IP "sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab"` |
| **Nodes `NotReady`** | Vérifier le CNI : `kubectl get pods -n calico-system` |
| **VMs pas d'internet** | Vérifier gateway : `ip route` doit montrer 192.168.1.1 |
| **Cloud-init ne s'exécute pas** | `cat /var/log/cloud-init.log` ou `sudo cloud-init clean && sudo reboot` |
| **Terraform : erreur snippet upload** | Vérifier `pvesm set local --content iso,vmtmpl,backup,snippets` |
| **Terraform : erreur disk size** | Le disque du template doit être plus petit que la taille cible |

### Reset complet d'un nœud

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
```

---

## Cheat sheet

```bash
# 1. Charger les secrets
source .env

# 2. Configurer
cp terraform/terraform.tfvars.example terraform/terraform.tfvars && vim terraform/terraform.tfvars

# 3. Provisionner
cd terraform && terraform init && terraform apply -auto-approve

# 4. Attendre cloud-init
ssh ubuntu@192.168.1.231 "cloud-init status --wait"

# 5. Init cluster
./scripts/init-control-plane.sh

# 6. Join workers
./scripts/join-workers.sh

# 7. Kubeconfig local
./scripts/copy-kubeconfig.sh

# 8. Vérifier
kubectl get nodes

# Détruire
./scripts/destroy-cluster.sh
```

---

> **Tip CKA :** Montez et détruisez ce cluster régulièrement. C'est exactement le type de tâche testée à l'examen (kubeadm init/join, troubleshooting de nœuds NotReady, etc.).
