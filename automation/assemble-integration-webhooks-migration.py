#!/usr/bin/env python3
"""Assemble/check the canonical additive integration webhook forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261114120000_integration_webhooks.sql')
