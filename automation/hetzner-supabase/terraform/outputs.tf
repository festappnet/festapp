output "server_id" {
  value = hcloud_server.supabase.id
}

output "ipv4_address" {
  value = hcloud_server.supabase.ipv4_address
}

output "ipv6_address" {
  value = hcloud_server.supabase.ipv6_address
}

output "next_step" {
  value = "Verify cloud-init and host hardening before installing the pinned Supabase bundle."
}
