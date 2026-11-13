#!/usr/bin/env python3
"""Assemble organizer metadata for notification settings."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261113110000_notification_settings_unit_groups.sql')
