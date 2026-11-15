#!/usr/bin/env python3
"""Assemble confirmation comparison normalization from its canonical owner."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261115190000_order_confirmation_seating_snapshot.sql')
