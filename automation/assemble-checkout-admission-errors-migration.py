#!/usr/bin/env python3
"""Assemble the checkout admission error forward from its canonical owner."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261115200000_checkout_admission_errors.sql')
