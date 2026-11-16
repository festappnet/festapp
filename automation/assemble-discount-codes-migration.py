#!/usr/bin/env python3
"""Assemble the canonical discount code forward; never applies it."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261115120000_discount_codes.sql', '20261115140000_discount_code_projections.sql')
