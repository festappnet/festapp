# Canonical Hetzner host

This module creates the protected, single-host rehearsal foundation for
Festapp's canonical Supabase stack in the same Hetzner project used by
Mendelio. It does not install Supabase, change DNS or touch either cloud source.
PostgreSQL is not exposed publicly.

The tracked defaults are an ARM `cax11` host in `nbg1`, Ubuntu 26.04 and
`environment=rehearsal`. Read `variables.tf` for the exact selected values.
These defaults preserve the original foundation; the module does not size a
production workload. Confirm current provider capacity and pricing before
provisioning. Historical cost and disk observations are not a current quote or
capacity check.

Measure available memory, OOM events and load latency. Reserve disk for database,
Storage, staging, temporary backup files and a restore rehearsal. Encrypted
off-host backups and verified restore evidence are required for production.
See [server deployment](../../../docs/setup/server_deployment.md) for runtime
requirements and the original host/promotion constraints.

## Prerequisites

1. Terraform matching `~> 1.16.0` and hcloud provider `1.68.0`, as declared
   in `versions.tf`.
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
