#!/usr/bin/env python3
"""Existing CLI boundary to the shared manifest-driven migration checker."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261110230000_ticket_wallet.sql')
