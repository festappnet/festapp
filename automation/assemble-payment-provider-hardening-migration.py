#!/usr/bin/env python3
"""Existing CLI boundary to the shared manifest-driven migration checker."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261106160000_payment_provider_hardening.sql', '20261106210000_restore_payment_configuration_null_resets.sql')
