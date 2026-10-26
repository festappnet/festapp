variable "server_name" {
  description = "Stable name of the canonical Festapp Supabase host."
  type        = string
  default     = "festapp-supabase-rehearsal-01"
}

variable "server_type" {
  description = "Low-cost ARM rehearsal shape matching the Mendelio Supabase host and price class."
  type        = string
  default     = "cax11"
}

variable "location" {
  description = "Hetzner location; location replaces the deprecated datacenter field."
  type        = string
  default     = "nbg1"
}

variable "image" {
  description = "Current Ubuntu LTS image selected by the runtime pin policy."
  type        = string
  default     = "ubuntu-26.04"
}

variable "ssh_key_ids" {
  description = "Existing Hetzner SSH key IDs allowed to bootstrap the host."
  type        = set(number)

  validation {
    condition     = length(var.ssh_key_ids) > 0
    error_message = "ssh_key_ids must contain at least one existing Hetzner SSH key ID."
  }
}

variable "admin_cidrs" {
  description = "Explicit administrator IPv4/IPv6 CIDRs allowed to reach SSH."
  type        = set(string)

  validation {
    condition = length(var.admin_cidrs) > 0 && alltrue([
      for cidr in var.admin_cidrs :
      can(cidrhost(cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], cidr)
    ])
    error_message = "admin_cidrs must contain explicit IPv4 or IPv6 CIDRs; 0.0.0.0/0 and ::/0 are forbidden."
  }
}

variable "environment" {
  description = "Infrastructure classification label."
  type        = string
  default     = "rehearsal"
}

variable "enable_backups" {
  description = "Paid Hetzner server backups; disabled for rehearsal, required disposition before production."
  type        = bool
  default     = false
}
