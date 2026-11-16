#!/usr/bin/env python3
"""Assemble/check the canonical ticket table-seat appearance migration."""
from migration_forward_owners import migration_cli

if __name__ == '__main__':
    migration_cli('20261116150000_ticket_table_seat_appearance.sql')
