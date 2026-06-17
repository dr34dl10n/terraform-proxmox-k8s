#!/usr/bin/env bash
# =============================================================
# init-control-plane.sh — Initialise le cluster Kubernetes
# Usage: ./init-control-plane.sh [CP_IP]
# =============================================================
set -euo pipefail

# --- Config (from common.sh: terraform output preferred, tfvars fallback) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# CLI override
if [ -n "${1:-}" ]; then
  CP_IP="$1"
fi

echo "================================================"
echo "🏗️  Initialisation du cluster Kubernetes"
echo "   Control Plane: ${SSH_USER}@${CP_IP}"
echo "================================================"

# --- 1. Vérifier que cloud-init est terminé ---
echo "⏳ Vérification que cloud-init est terminé..."
ssh "${SSH_USER}@${CP_IP}" "cloud-init status --wait" 2>/dev/null || {
  echo "⚠️  Impossible de vérifier cloud-init. Continuez quand même? (y/n)"
  read -r answer
  [ "$answer" = "y" ] || exit 1
}
echo "✅ Cloud-init terminé"

# --- 2. Remplacer l'IP dans la config kubeadm ---
echo "📝 Préparation de la config kubeadm..."
ssh "${SSH_USER}@${CP_IP}" "sudo sed -i 's/CP_IP_REPLACE/${CP_IP}/g' /etc/kubeadm/kubeadm-config.yaml" 2>/dev/null || true

# --- 3. kubeadm init ---
echo "🚀 Exécution de kubeadm init..."
ssh "${SSH_USER}@${CP_IP}" << 'INIT_EOF'
sudo kubeadm init \
  --config /etc/kubeadm/kubeadm-config.yaml \
  --upload-certs \
  2>&1 | sudo tee /var/log/kubeadm-init.log

# Configurer kubeconfig pour l'utilisateur ubuntu ET pour root
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# KUBECONFIG pour root (indispensable pour les scripts de diagnostic)
sudo mkdir -p /root/.kube
sudo cp /etc/kubernetes/admin.conf /root/.kube/config
sudo chown root:root /root/.kube/config

# Variable d'env KUBECONFIG globale (pour root et ubuntu)
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' | sudo tee /etc/profile.d/kubeconfig.sh > /dev/null
sudo chmod +x /etc/profile.d/kubeconfig.sh

echo "✅ kubeconfig configuré (ubuntu + root + /etc/profile.d)"
INIT_EOF

echo ""
echo "✅ kubeadm init terminé !"

# --- 4. Installer le CNI (Calico) ---
echo "🌐 Installation du CNI Calico..."
ssh "${SSH_USER}@${CP_IP}" << 'CNI_EOF'
export KUBECONFIG=$HOME/.kube/config
set -e

# --- Installation du tigera-operator ---
# server-side apply OBLIGATOIRE ici : le CRD installations.operator.tigera.io a un
# schéma OpenAPI si volumineux que l'annotation `last-applied-configuration` (écrite
# par `kubectl apply` client-side) dépasse la limite K8s de 256 KB sur les annotations
# → "metadata.annotations: Too long: must have at most 262144 bytes".
# `--server-side` gère l'appartenance via managedFields (pas d'annotation) et reste
# idempotent (re-run sans reset OK). `--force-conflicts` = no-op si pas de conflit.
kubectl apply --server-side --force-conflicts -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

# --- Attendre que le CRD "Installation" soit établi avant d'appliquer la CR ---
# Sinon race condition : `kubectl apply` retourne avant que l'API server ne serve
# le nouveau kind → "no matches for kind Installation in version operator.tigera.io/v1"
echo "⏳ Attente de l'établissement du CRD installations.operator.tigera.io..."
timeout 120 bash -c 'until kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; do sleep 1; done'
kubectl wait --for=condition=Established --timeout=120s crd/installations.operator.tigera.io

# Appliquer custom-resources avec le CIDR correct (10.244.0.0/16 au lieu du default 192.168.0.0/16)
# ⚠️ natOutgoing doit être une CHAÎNE ("Enabled"/"Disabled"), pas un booléen (true/false)
#     sinon l'API tigera-operator rejette la CR et Calico n'est jamais configuré.
kubectl apply -f - <<CALICO_CR
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
CALICO_CR

echo "✅ Calico CNI: tigera-operator + Installation appliqués (pod CIDR=10.244.0.0/16)"
echo "⏳ L'opérateur reconciled en cours — patientez ~1-3 min avant que les nodes passent Ready."
echo "   Vérif: kubectl get nodes -w  |  kubectl get pods -A | grep -E 'tigera|calico'"
CNI_EOF

# --- 5. Installer le metrics-server ---
echo "📊 Installation du metrics-server..."
ssh "${SSH_USER}@${CP_IP}" << 'METRICS_EOF'
export KUBECONFIG=$HOME/.kube/config

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Patch : kubelet-insecure-tls nécessaire en lab (certs auto-signés)
kubectl patch deploy metrics-server -n kube-system --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true
echo "✅ metrics-server installé"
METRICS_EOF

# --- 6. Afficher la commande join ---
echo ""
echo "================================================"
echo "🎉 Cluster initialisé ! Prochaines étapes :"
echo ""
echo "  1) Attendre que les nœuds soient Ready :"
echo "     ssh ${SSH_USER}@${CP_IP} 'kubectl get nodes -w'"
echo ""
echo "  2) Joindre les workers :"
echo "     ${SCRIPT_DIR}/join-workers.sh"
echo ""
echo "  3) Récupérer le kubeconfig localement :"
echo "     ${SCRIPT_DIR}/copy-kubeconfig.sh"
echo "================================================"