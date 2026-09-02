# Canonical Hetzner host

This module creates the protected, single-host rehearsal foundation for
Festapp's canonical Supabase stack in the same Hetzner project used by
Mendelio. It does not install Supabase, change DNS or touch either cloud source.
PostgreSQL is not exposed publicly.

The default is the same low-cost ARM `CAX11` class used by Mendelio Supabase in
`nbg1`: 2 shared vCPU, 4 GB RAM and 40 GB local disk. As of 2026-08-27 the live
account quotes EUR 7.2479/month gross plus EUR 0.605/month gross for IPv4, or
EUR 7.8529/month total. Paid Hetzner backups add 20% of the server price and are
disabled for the rehearsal, making the backup-enabled total EUR 9.30248/month.

Linux cache usage is not treated as RAM exhaustion. The rehearsal must measure
available memory, OOM events and p95/p99 under load. Disk is a separate hard
gate: the current Mendelio CAX11 happens to be 97% full, so Festapp must prove
restore/staging headroom on a clean host before CAX11 can become production.
Encrypted off-host PostgreSQL/Storage backups remain mandatory for production.

## Prerequisites

1. Terraform `1.16.1` and hcloud provider `1.68.0`.
2. A least-privilege Hetzner project token exported as `HCLOUD_TOKEN`.
3. Existing Hetzner SSH key IDs and explicit administrator `/32` or `/128`
   source CIDRs in a private `.tfvars` file outside Git.

Run `terraform init`, `terraform validate` and `terraform plan -out=...` first.
Review the plan and current Hetzner price before `terraform apply`. The resource
has both Hetzner delete/rebuild protection and Terraform `prevent_destroy`.
Never use `terraform destroy` for this stack.

Configure the local backend to a private path outside the repository, for
example with `terraform init -backend-config=path=/private/terraform.tfstate`.
Never commit state, plans or real `.tfvars` files.
