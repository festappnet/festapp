#!/usr/bin/env python3
"""Assemble the explicit cash default policy forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261112220000_cash_policy_defaults.sql')
