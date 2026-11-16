#!/usr/bin/env python3
"""Assemble the additive customer self-service completion forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261115160000_customer_self_service_completion.sql')
