#!/usr/bin/env python3
"""Assemble the explicit notification preference simplification forward."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261113014000_notification_settings_clarity.sql')
