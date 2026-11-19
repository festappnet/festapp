#!/usr/bin/env python3
"""Assemble the organizer ticket resend migration from canonical sources."""
from migration_forward_owners import migration_cli

if __name__ == '__main__':
    migration_cli('20261119230000_organizer_ticket_resend_limits.sql')
