#!/usr/bin/env python3
"""Render additive and guarded contraction Wallet queue migrations."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261113090000_ticket_wallet_queue_expand.sql', '20261113090100_ticket_wallet_queue_contract.sql')
