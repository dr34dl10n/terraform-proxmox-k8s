#!/usr/bin/env bash
# =============================================================
# copy-kubeconfig.sh — Récupère le kubeconfig du CP localement
# Usage: ./copy-kubeconfig.sh [CP_IP]
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TFVARS="${PROJECT_DIR}/terraform/terraform.tfvars"

# --- Config ---
if [ -n "${1:-}" ]; then
  CP_IP="$1"
elif [ -f "$TFVARS" ]; then
  CP_IP=$(grep -E '^control_plane_ip' "$TFVARS" | sed 's/.*=.*"\(.*\)".*/\1/' | tr -d '"')
  SSH_USER=$(grep -E '^ssh_user' "$TFVARS" | sed 's/.*=.*"\(.*\)".*/\1/' | tr -d '"' || echo "ubuntu")
else
  CP_IP="192.168.1.231"
  SSH_USER="ubuntu"
fi

KUBECONFIG_LOCAL="${HOME}/.kube/config.k8s-lab"
KUBECONFIG_MERGED="${HOME}/.kube/config"

echo "================================================"
echo "📋 Copie du kubeconfig depuis ${SSH_USER}@${CP_IP}"
echo "================================================"

# --- 1. Créer le répertoire .kube localement ---
mkdir -p "${HOME}/.kube"

# --- 2. Récupérer le kubeconfig ---
echo "📦 Téléchargement du kubeconfig..."
scp "${SSH_USER}@${CP_IP}":.kube/config "${KUBECONFIG_LOCAL}"

# --- 3. Remplacer l'IP interne par l'IP du CP ---
# Souvent le kubeconfig pointe vers 127.0.0.1, on le remplace
# par l'IP réelle pour pouvoir l'utiliser à distance
sed -i "s/127.0.0.1/${CP_IP}/g" "${KUBECONFIG_LOCAL}"
sed -i "s/server: https:\/\/10\./server: https:\/\/${CP_IP}/g" "${KUBECONFIG_LOCAL}" 2>/dev/null || true

echo "✅ kubeconfig sauvé dans : ${KUBECONFIG_LOCAL}"

# --- 4. Proposer de merger ---
echo ""
echo "Pour utiliser ce kubeconfig :"
echo ""
echo "  Option 1 — Temporaire :"
echo "    export KUBECONFIG=${KUBECONFIG_LOCAL}"
echo "    kubectl get nodes"
echo ""
echo "  Option 2 — Merge avec votre config existante :"
echo "    export KUBECONFIG=${KUBECONFIG_MERGED}:${KUBECONFIG_LOCAL}"
echo "    kubectl config use-context kubernetes-admin@kubernetes"
echo ""
echo "  Option 3 — Remplacer votre config par défaut :"
echo "    cp ${KUBECONFIG_LOCAL} ${KUBECONFIG_MERGED}"
echo ""
echo "================================================"