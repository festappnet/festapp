#!/usr/bin/env python3
"""Assemble the additive Apple Wallet connector migration."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261113180000_apple_ticket_wallet.sql')
