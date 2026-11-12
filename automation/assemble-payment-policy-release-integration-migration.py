#!/usr/bin/env python3
"""Assemble the explicit current-main integration forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261112210000_payment_policy_release_integration.sql')
