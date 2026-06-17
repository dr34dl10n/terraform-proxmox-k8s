#cloud-config
# =============================================================
# Cloud-Init ${node_type} — Préparation complète du nœud
# Template unique (DRY) — rendu via terraform templatefile()
# Les parties CP-only sont conditionnées par is_control_plane
# =============================================================

hostname: ${hostname}
preserve_hostname: false

disable_root: false
ssh_pwauth: false

package_update: true
package_upgrade: ${package_upgrade}

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
  - jq
  - vim
  - bash-completion

write_files:
  # --- Modules kernel requis par Kubernetes ---
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # --- Paramètres sysctl pour le networking Kubernetes ---
  # /etc/sysctl.d/k8s.conf  — nom attendu par kubeadm et les scripts de check
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

  # --- crictl config ---
  - path: /etc/crictl.yaml
    content: |
      runtime-endpoint: unix:///run/containerd/containerd.sock
      image-endpoint: unix:///run/containerd/containerd.sock
      timeout: 10
      debug: false

  # --- containerd config (écrit AVANT runcmd pour être présent dès l'install) ---
  - path: /etc/containerd/config.toml
    owner: root:root
    permissions: '0644'
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
%{ if is_control_plane }

  # --- Config kubeadm pour init ---
  # CP_IP_REPLACE sera remplacé par le script init-control-plane.sh
  - path: /etc/kubeadm/kubeadm-config.yaml
    owner: root:root
    permissions: '0644'
    content: |
      apiVersion: kubeadm.k8s.io/v1beta4
      kind: InitConfiguration
      nodeRegistration:
        criSocket: unix:///run/containerd/containerd.sock
        kubeletExtraArgs:
          - name: cgroup-driver
            value: systemd
      ---
      apiVersion: kubeadm.k8s.io/v1beta4
      kind: ClusterConfiguration
      kubernetesVersion: "v1.31.0"
      controlPlaneEndpoint: "CP_IP_REPLACE:6443"
      networking:
        podSubnet: "10.244.0.0/16"
        serviceSubnet: "10.96.0.0/12"
      ---
      apiVersion: kubelet.config.k8s.io/v1beta1
      kind: KubeletConfiguration
      cgroupDriver: "systemd"
%{ else }

  # --- Config kubeadm pour join (les tokens seront fournis par le script) ---
  - path: /etc/kubeadm/kubeadm-config.yaml
    owner: root:root
    permissions: '0644'
    content: |
      apiVersion: kubeadm.k8s.io/v1beta4
      kind: JoinConfiguration
      nodeRegistration:
        criSocket: unix:///run/containerd/containerd.sock
        kubeletExtraArgs:
          - name: cgroup-driver
            value: systemd
      discovery:
        bootstrapToken:
          apiServerEndpoint: "CP_IP_REPLACE:6443"
          token: ""
          caCertHashes: []
      ---
      apiVersion: kubelet.config.k8s.io/v1beta1
      kind: KubeletConfiguration
      cgroupDriver: "systemd"
%{ endif }

runcmd:
  # --- Charger les modules kernel ---
  - modprobe overlay
  - modprobe br_netfilter

  # --- Appliquer les sysctl ---
  - sysctl --system

  # --- Désactiver le swap (OBLIGATOIRE pour Kubernetes) ---
  - swapoff -a
  - sed -i '/swap/d' /etc/fstab

  # --- Configurer containerd AVANT l'install (write_files se produit avant runcmd) ---
  # Le fichier est écrit via write_files ci-dessous pour garantir sa présence.

  # --- Installer containerd ---
  - apt-get install -y containerd

  # --- Ré-écrire la config containerd (apt peut écraser notre fichier) ---
  - |
    cat > /etc/containerd/config.toml <<CONTAINERD_EOF
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
    CONTAINERD_EOF

  # --- Redémarrer containerd avec la bonne config ---
  - systemctl restart containerd
  - systemctl enable containerd

  # --- Ajouter la clé GPG du dépôt Kubernetes ---
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  # --- Ajouter le dépôt Kubernetes ---
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

  # --- Installer kubeadm, kubelet, kubectl ---
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl containerd

  # --- Activer kubelet ---
  - systemctl enable kubelet

  # --- Configurer KUBECONFIG global (root + ubuntu) ---
  - mkdir -p /root/.kube
  - mkdir -p /home/ubuntu/.kube

  # --- Activer bash-completion pour kubectl (ubuntu + root) ---
  - echo 'source <(kubectl completion bash)' >> /home/ubuntu/.bashrc
  - echo 'alias k=kubectl' >> /home/ubuntu/.bashrc
  - echo 'complete -o default -F __start_kubectl k' >> /home/ubuntu/.bashrc
  - echo 'source <(kubectl completion bash)' >> /root/.bashrc
  - echo 'alias k=kubectl' >> /root/.bashrc
  - echo 'complete -o default -F __start_kubectl k' >> /root/.bashrc

  # --- Installer etcdctl (outil de diagnostic CKA) ---
  # Version fixe pour la reproductibilité (v3.5.17 = dernière stable)
  - |
    ETCDCTL_VER="3.5.17"
    curl -sL "https://github.com/etcd-io/etcd/releases/download/v$${ETCDCTL_VER}/etcd-v$${ETCDCTL_VER}-linux-amd64.tar.gz" | tar xz -C /tmp && cp "/tmp/etcd-v$${ETCDCTL_VER}-linux-amd64/etcdctl" /usr/local/bin/ && chmod +x /usr/local/bin/etcdctl && echo "✅ etcdctl v$${ETCDCTL_VER} installé"

  # --- Message de fin ---
  - echo "========================================="
%{ if is_control_plane }
  - 'echo "✅ Control Plane cloud-init: DONE"'
%{ else }
  - 'echo "✅ Worker cloud-init: DONE"'
%{ endif }
  - 'echo "✅ containerd: configured (systemd cgroup)"'
  - 'echo "✅ kubeadm/kubelet/kubectl: installed (v1.31)"'
  - 'echo "✅ swap: disabled"'
  - 'echo "✅ kernel modules: loaded"'
%{ if is_control_plane }
  - 'echo "⏳ Next: run kubeadm init (or init-control-plane.sh)"'
%{ else }
  - 'echo "⏳ Next: run kubeadm join (or join-workers.sh)"'
%{ endif }
  - echo "========================================="