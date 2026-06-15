# =============================================================
# Main — Provisionnement des VMs Kubernetes sur Proxmox
# Utilise proxmox_virtual_environment_vm (API native bpg)
# + cloud-init rendu via templatefile() + source_raw (DRY)
# =============================================================

# --- Rendu des cloud-init depuis un template unique ---
locals {
  cp_user_data = templatefile("${path.module}/../cloud-init/user-data.yaml.tpl", {
    is_control_plane = true
    node_type        = "Control Plane"
    package_upgrade  = false
    hostname         = "${var.cluster_name}-cp"
  })

  worker_user_data = {
    for i, ip in var.worker_ips :
    "w${i + 1}" => templatefile("${path.module}/../cloud-init/user-data.yaml.tpl", {
      is_control_plane = false
      node_type        = "Worker"
      package_upgrade  = false
      hostname         = "${var.cluster_name}-w${i + 1}"
    })
  }
}

# --- Upload des snippets cloud-init ---
resource "proxmox_virtual_environment_file" "cp_user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_storage
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    data      = local.cp_user_data
    file_name = "control-plane-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "worker_user_data" {
  for_each    = local.worker_user_data
  content_type = "snippets"
  datastore_id = var.snippets_storage
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    data      = each.value
    file_name = "worker-${each.key}-user-data.yaml"
  }
}

# --- Définition des nœuds (DRY : une seule ressource avec for_each) ---
locals {
  control_plane_node = {
    vm_id         = 101
    name          = "${var.cluster_name}-cp"
    description   = "Kubernetes Control Plane Node"
    cores         = var.control_plane_cores
    memory        = var.control_plane_memory
    ip            = var.control_plane_ip
    tags          = ["k8s", "control-plane"]
    startup_order = 1
    user_data_id  = proxmox_virtual_environment_file.cp_user_data.id
  }

  worker_nodes = {
    for i, ip in var.worker_ips :
    "w${i + 1}" => {
      vm_id         = 102 + i
      name          = "${var.cluster_name}-w${i + 1}"
      description   = "Kubernetes Worker Node ${i + 1}"
      cores         = var.worker_cores
      memory        = var.worker_memory
      ip            = ip
      tags          = ["k8s", "worker"]
      startup_order = 2
      user_data_id  = proxmox_virtual_environment_file.worker_user_data["w${i + 1}"].id
    }
  }

  all_nodes = merge(
    { cp = local.control_plane_node },
    local.worker_nodes,
  )
}

# --- VMs Kubernetes (Control Plane + Workers) ---
resource "proxmox_virtual_environment_vm" "node" {
  for_each    = local.all_nodes
  vm_id       = each.value.vm_id
  name        = each.value.name
  description = each.value.description
  node_name   = var.proxmox_node
  tags        = each.value.tags

  # --- Clone depuis le template ---
  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = 3
  }

  # --- CPU ---
  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  # --- Mémoire ---
  memory {
    dedicated = each.value.memory
  }

  # --- Disque ---
  disk {
    datastore_id = var.vm_disk_storage
    interface    = "scsi0"
    size         = var.vm_disk_size
  }

  # --- Réseau ---
  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  # --- Cloud-Init ---
  initialization {
    interface    = "ide2"
    datastore_id = var.vm_disk_storage

    user_account {
      username = var.ssh_user
      keys     = [var.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${split("/", var.vm_network_cidr)[1]}"
        gateway = var.vm_gateway
      }
    }

    dns {
      servers = var.vm_dns_servers
    }

    # Injection du user-data custom (packages, containerd, kubeadm, etc.)
    user_data_file_id = each.value.user_data_id
  }

  # --- QEMU Guest Agent ---
  agent {
    enabled = true
  }

  # --- Boot & démarrage automatique ---
  startup {
    order = each.value.startup_order
  }

  # --- Éviter le re-apply du cloud-init après le premier apply ---
  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}