#!/usr/bin/env python3
"""Assemble the explicit historical scanner ownership contraction."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261113013000_scanner_ownership_contraction.sql')
