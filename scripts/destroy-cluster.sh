#!/usr/bin/env bash
# =============================================================
# destroy-cluster.sh — Nettoyage complet du lab Kubernetes
#   1. Reset kubeadm sur chaque nœud
#   2. Détruit les VMs via Terraform
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TFVARS="${PROJECT_DIR}/terraform/terraform.tfvars"
TERRAFORM_DIR="${PROJECT_DIR}/terraform"

# --- Récupérer les IPs ---
if [ -f "$TFVARS" ]; then
  CP_IP=$(grep -E '^control_plane_ip' "$TFVARS" | sed 's/.*=.*"\(.*\)".*/\1/' | tr -d '"')
  WORKER_IPS=$(grep -E '^worker_ips' "$TFVARS" | sed 's/.*=.*\[\(.*\)\].*/\1/' | tr -d '"' | tr ',' ' ')
  SSH_USER=$(grep -E '^ssh_user' "$TFVARS" | sed 's/.*=.*"\(.*\)".*/\1/' | tr -d '"' || echo "ubuntu")
else
  CP_IP="192.168.1.231"
  WORKER_IPS="192.168.1.232 192.168.1.233"
  SSH_USER="ubuntu"
fi

echo "================================================"
echo "💣 Destruction du lab Kubernetes"
echo "================================================"

# --- 1. Reset kubeadm sur chaque nœud (optionnel, TF détruit les VMs) ---
echo ""
echo "⚠️  Voulez-vous reset kubeadm avant de détruire les VMs ? (y/n)"
echo "   (Utile si vous gardez les VMs mais veux juste détruire le cluster K8s)"
read -r answer

if [ "$answer" = "y" ]; then
  ALL_IPS="$CP_IP $WORKER_IPS"
  for IP in $ALL_IPS; do
    echo "🔄 Reset de ${IP}..."
    ssh "${SSH_USER}@${IP}" << 'RESET_EOF' 2>/dev/null || echo "⚠️  Impossible de reset ${IP} (VM peut-être déjà éteinte)"
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo ipvsadm --clear 2>/dev/null || true
echo "✅ ${HOSTNAME} reset done"
RESET_EOF
  done
  echo "✅ kubeadm reset terminé sur tous les nœuds"
fi

# --- 2. Détruire les VMs avec Terraform ---
echo ""
echo "💣 Destruction des VMs Proxmox avec Terraform..."
cd "$TERRAFORM_DIR"

if [ ! -f ".terraform/terraform.tfstate" ] && [ ! -f "terraform.tfstate" ]; then
  echo "❌ Aucun state Terraform trouvé. Les VMs seront peut-être toujours présente sur Proxmox."
  echo "   Supprimez-les manuellement ou vérifiez le state."
  exit 1
fi

terraform destroy -auto-approve

echo ""
echo "================================================"
echo "✅ Lab détruit !"
echo "   Pour recréer : cd terraform && terraform apply -auto-approve"
echo "================================================"