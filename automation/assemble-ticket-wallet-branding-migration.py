#!/usr/bin/env python3
"""Assemble the scoped Wallet branding and preview forward migration."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261112233000_ticket_wallet_branding.sql')
