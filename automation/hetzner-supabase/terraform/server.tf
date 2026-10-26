resource "hcloud_server" "supabase" {
  name         = var.server_name
  image        = var.image
  server_type  = var.server_type
  location     = var.location
  ssh_keys     = var.ssh_key_ids
  firewall_ids = [hcloud_firewall.supabase.id]

  backups            = var.enable_backups
  delete_protection  = true
  rebuild_protection = true
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname = var.server_name
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    application = "festapp"
    role        = "canonical-supabase"
    environment = var.environment
    managed_by  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}
