#!/usr/bin/env python3
"""Assemble the configured-bank setup projection forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261112230000_order_bank_setup_projection.sql')
