#!/usr/bin/env python3
"""Assemble the guarded cancellation-only forward cutover."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261116010000_customer_cancellation_cutover.sql')
