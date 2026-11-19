#!/usr/bin/env python3
"""Assemble verified transactional email admission from canonical sources."""
from migration_forward_owners import migration_cli

if __name__ == '__main__':
    migration_cli('20261120020000_transactional_order_email_admission.sql')
