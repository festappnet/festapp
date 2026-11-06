#!/usr/bin/env python3
"""Assemble only the confirmed seat-order migration from its canonical owners."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    'inventory/lock_spot_assignment_scope_internal_v1.sql',
    'eshop_orders/amount_changes.sql',
    'eshop/swap_spot_tickets.sql',
    'eshop/release_blueprint_holds_client_sync_v1.sql',
    'eshop_orders/replacement_invoice_preparation.sql',
    'blueprint/apply_seat_swap_internal.sql',
    'blueprint/swap_command_internal.sql',
    'blueprint/seat_swap.sql',
    'blueprint/order_input.sql',
    'blueprint/order_conflicts.sql',
    'eshop/analyze_new_order_spots.sql',
    'eshop/confirm_blueprint_order_change.sql',
    'blueprint/order_selection.sql',
    'blueprint/apply_seat_order_internal.sql',
    'blueprint/order_quote.sql',
    'blueprint/order_rejection.sql',
    'blueprint/order_command_internal.sql',
    'eshop_orders/replace_blueprint_order_client_sync_v1.sql',
    'blueprint/seat_orders.sql',
)
TARGET = ROOT / 'supabase/migrations/20261024023000_confirmed_blueprint_seat_orders.sql'
# This release has an installed ledger identity. Later canonical changes belong
# to forward migrations, just as the batch and seating migration owners do.
import hashlib
from generate_canonical_source_contract import render, TARGET as CONTRACT
expected = '41cbed8f437bac0826cf0b30c99f2b30ab4bd472de5247221a24dae51585f9c2'
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != expected:
    raise SystemExit('Installed seat-order migration bytes changed')
if '--check' not in sys.argv:
    raise SystemExit('Installed seat-order migration is immutable; author a forward migration')
if CONTRACT.read_text() != render(ROOT):
    raise SystemExit('Current canonical source parity is stale')
