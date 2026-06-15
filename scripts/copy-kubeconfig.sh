#!/usr/bin/env bash
# =============================================================
# copy-kubeconfig.sh — Récupère le kubeconfig du CP localement
# Usage: ./copy-kubeconfig.sh [CP_IP]
# =============================================================
set -euo pipefail

# --- Config (from common.sh: terraform output preferred, tfvars fallback) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# CLI override
if [ -n "${1:-}" ]; then
  CP_IP="$1"
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