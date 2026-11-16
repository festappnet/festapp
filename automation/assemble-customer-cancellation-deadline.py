#!/usr/bin/env python3
"""Assemble the event-start cancellation deadline forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261116020000_customer_cancellation_default_deadline.sql')
