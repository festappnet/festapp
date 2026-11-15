#!/usr/bin/env python3
"""Assemble/check the additive, inactive customer self-service foundation."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261115130000_customer_order_policy_foundation.sql')
