#!/usr/bin/env python3
"""Assemble/check the generated readiness-contract forward without rewriting history."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261114130000_ticket_layout_contract_refresh.sql')
