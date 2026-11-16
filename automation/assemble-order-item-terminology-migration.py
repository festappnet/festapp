#!/usr/bin/env python3
"""Assemble the registered presentation-only terminology forward."""
from migration_forward_owners import migration_cli

if __name__ == '__main__':
    migration_cli('20261114233000_order_item_terminology.sql')
