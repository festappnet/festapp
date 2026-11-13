#!/usr/bin/env python3
"""Assemble the explicit notification payment channel forward migration."""
from migration_forward_owners import migration_cli
if __name__ == '__main__':
    migration_cli('20261113123000_notification_payment_channels.sql')
