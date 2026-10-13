#!/usr/bin/env python3
"""Assemble the reviewed form-capacity migration from canonical SQL."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    'database/functions/eshop_waitlist/schema.sql',
    'database/functions/eshop_waitlist/form_capacity.sql',
    'database/functions/eshop_waitlist/participants.sql',
    'database/functions/eshop_waitlist/capabilities.sql',
    'database/functions/eshop_waitlist/offers.sql',
    'database/functions/eshop_waitlist/accept_offer.sql',
    'database/functions/eshop_waitlist/commands.sql',
    'database/functions/eshop_waitlist/email_context.sql',
    'database/functions/eshop_waitlist/email_render_context.sql',
    'database/functions/eshop_waitlist/email_templates.sql',
    'database/functions/eshop_waitlist/email_preview.sql',
    'database/functions/eshop_waitlist/fakturoid_recovery.sql',
    'database/functions/eshop/finalize_ticket_order.sql',
    'database/functions/eshop/create_ticket_order.sql',
    'database/functions/eshop_forms/update_form.sql',
    'database/functions/eshop_forms/get_form_by_link.sql',
    'database/functions/eshop_forms/get_all_forms_with_fields.sql',
    'database/functions/eshop_forms/get_form_for_edit.sql',
    'database/functions/eshop_forms/duplicate_form_to_occasion.sql',
    'database/functions/others/duplicate_occasion.sql',
    'database/functions/eshop_orders/check_order_is_mutable.sql',
    'database/functions/eshop_orders/internal_storno_tickets_221.sql',
    'database/functions/eshop_orders/update_order_and_tickets_to_storno_ws.sql',
    'database/functions/eshop_orders/storno_tickets_client_sync_v1.sql',
    'database/functions/eshop_orders/storno_tickets_bulk.sql',
    'database/functions/eshop_orders/update_ticket_products_ws.sql',
    'database/functions/eshop_orders/update_order_note_hidden.sql',
    'database/functions/eshop_orders/get_orders.sql',
    'database/functions/eshop/update_product.sql',
    'database/functions/inventory/apply_allocations.sql',
    'database/functions/inventory/update_product_inventory_contexts.sql',
    'database/functions/inventory/update_inventory_pool_bundle.sql',
    'database/functions/inventory/adjust_spot_capacity_for_pool.sql',
    'database/functions/emails/email_queue.sql',
    'database/functions/emails/fakturoid_email_gate.sql',
    'database/functions/eshop/get_report_ws.sql',
    'database/functions/eshop_forms/get_forms_by_link.sql',
    'database/functions/eshop_forms/get_form.sql',
    'database/functions/eshop_orders/delete_order.sql',
    'database/functions/seed/crons.sql',
    'database/functions/eshop_waitlist/client_sync.sql',
    'database/functions/eshop/product_write_permissions.sql',
]
TARGET = ROOT / "supabase/migrations/20261013190000_form_capacity_waitlist.sql"
content = "-- Canonical form-capacity and waitlist expansion. Additive defaults keep existing forms unlimited.\n"
for source in SOURCES:
    content += "\n-- Source: " + source + "\n" + (ROOT / source).read_text() + "\n"
TARGET.write_text(content.rstrip() + "\n")
print("Form-capacity migration assembled")
