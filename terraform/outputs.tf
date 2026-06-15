# =============================================================
# Outputs — Informations utiles post-déploiement
# =============================================================

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

output "ssh_command_workers" {
  value = [
    for ip in var.worker_ips : "ssh ${var.ssh_user}@${ip}"
  ]
  description = "Commandes SSH pour les Workers"
}

output "ssh_user" {
  value       = var.ssh_user
  description = "Utilisateur SSH pour les nœuds"
}

output "kubeadm_init_hint" {
  value       = "👉 Après cloud-init terminé, lancez : ./scripts/init-control-plane.sh"
  description = "Prochaine étape après le déploiement"
}

output "all_node_ips" {
  value       = concat([var.control_plane_ip], var.worker_ips)
  description = "Toutes les IPs du cluster"
}