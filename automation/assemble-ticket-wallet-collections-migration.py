#!/usr/bin/env python3
"""Assemble the additive, explicitly scoped multi-ticket Wallet migration."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261114010000_ticket_wallet_collections.sql')
