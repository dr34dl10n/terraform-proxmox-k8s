#!/usr/bin/env bash
# =============================================================
# destroy-cluster.sh — Nettoyage complet du lab Kubernetes
#   1. Reset kubeadm sur chaque nœud
#   2. Détruit les VMs via Terraform
# =============================================================
set -euo pipefail

# --- Config (from common.sh: terraform output preferred, tfvars fallback) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/common.sh"

TERRAFORM_DIR="${PROJECT_DIR}/terraform"

echo "================================================"
echo "💣 Destruction du lab Kubernetes"
echo "================================================"

# --- 1. Reset kubeadm sur chaque nœud (optionnel, TF détruit les VMs) ---
echo ""
echo "⚠️  Voulez-vous reset kubeadm avant de détruire les VMs ? (y/n)"
echo "   (Utile si vous gardez les VMs mais voulez juste détruire le cluster K8s)"
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

if [ ! -f "terraform.tfstate" ]; then
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