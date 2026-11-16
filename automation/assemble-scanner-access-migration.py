#!/usr/bin/env python3
"""Assemble and verify the explicit scanner access forward migration."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261112235500_scanner_occasion_isolation.sql')
