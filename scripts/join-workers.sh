#!/usr/bin/env bash
# =============================================================
# join-workers.sh — Joint les workers au cluster Kubernetes
# Usage: ./join-workers.sh [CP_IP] [W1_IP W2_IP ...]
# =============================================================
set -euo pipefail

# --- Config (from common.sh: terraform output preferred, tfvars fallback) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# CLI overrides
if [ -n "${1:-}" ]; then
  CP_IP="$1"
  shift
fi
if [ $# -gt 0 ]; then
  WORKER_IPS="$*"
fi

echo "================================================"
echo "🔗 Jointure des Workers au cluster"
echo "   Control Plane: ${CP_IP}"
echo "   Workers: ${WORKER_IPS}"
echo "================================================"

# --- 1. Récupérer la commande join depuis le CP ---
echo "📌 Récupération du token kubeadm join..."
JOIN_CMD=$(ssh "${SSH_USER}@${CP_IP}" "kubeadm token create --print-join-command" 2>/dev/null)

if [ -z "$JOIN_CMD" ]; then
  echo "❌ Impossible de récupérer la commande join. Le Control Plane est-il prêt ?"
  exit 1
fi

echo "✅ Commande join récupérée :"
echo "   ${JOIN_CMD}"
echo ""

# --- 2. Exécuter kubeadm join sur chaque worker ---
i=1
for W_IP in $WORKER_IPS; do
  echo "🔗 Jointure du Worker ${i} (${W_IP})..."

  # Vérifier que cloud-init est fini
  ssh "${SSH_USER}@${W_IP}" "cloud-init status --wait" 2>/dev/null || true

  # Remplacer l'IP dans la config kubeadm join
  ssh "${SSH_USER}@${W_IP}" "sudo sed -i 's/CP_IP_REPLACE/${CP_IP}/g' /etc/kubeadm/kubeadm-config.yaml" 2>/dev/null || true

  # Exécuter le join
  ssh "${SSH_USER}@${W_IP}" "sudo ${JOIN_CMD}" 2>&1

  if [ $? -eq 0 ]; then
    echo "✅ Worker ${i} (${W_IP}) joint au cluster !"
  else
    echo "❌ Erreur lors de la jointure du Worker ${i} (${W_IP})"
  fi
  echo ""
  i=$((i + 1))
done

# --- 3. Vérification ---
echo "================================================"
echo "🎉 Workers joints ! Vérification :"
echo ""
echo "  ssh ${SSH_USER}@${CP_IP} 'kubectl get nodes'"
echo ""
echo "  Tous les nœuds doivent passer en 'Ready'"
echo "  (ça peut prendre ~1-2 min pour le CNI Calico)"
echo "================================================"