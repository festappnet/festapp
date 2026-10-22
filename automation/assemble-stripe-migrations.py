#!/usr/bin/env python3
"""Assemble unpublished Stripe migrations from their canonical SQL owners."""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = {
    "20261022160000_stripe_foundation.sql": (
        "Stripe foundation only; new payments disabled. No production application authorized.",
        ["eshop_stripe/schema.sql", "eshop_stripe/feature_settings.sql", "eshop_stripe/capabilities.sql",
         "eshop_transactions/payment_totals.sql", "eshop_transactions/apply_transaction_pairing.sql"],
    ),
    "20261022170000_stripe_connections.sql": (
        "Stripe unit authorization and durable OAuth intent boundary. Requires Stripe foundation.",
        ["eshop_stripe/connections_schema.sql", "eshop_stripe/connection_status_schema.sql", "eshop_stripe/disconnect_schema.sql", "eshop_stripe/abuse.sql", "abuse/policy.sql", "eshop_stripe/connections.sql", "eshop_stripe/connection_status.sql", "eshop_stripe/disconnect.sql"],
    ),
    "20261022180000_stripe_checkout_ingest.sql": (
        "Stripe checkout, atomic provider facts and domain guards. Unpublished; no pilot activation.",
        ["public_links/reserved_paths.sql", "eshop_stripe/checkout_schema.sql", "eshop_stripe/checkout_abuse.sql", "abuse/policy.sql",
         "eshop_stripe/form_availability.sql", "eshop_stripe/form_recipient.sql", "eshop_stripe/order_creation.sql", "eshop_stripe/checkout.sql", "eshop_stripe/handoff.sql",
         "eshop_stripe/ingest.sql", "eshop_stripe/reconciliation.sql", "eshop_stripe/admission.sql", "eshop_stripe/refund_decisions.sql", "eshop_stripe/admin_detail.sql",
         "scanning/projection.sql", "scanning/admission.sql", "eshop_orders/scan_ticket.sql",
         "eshop_orders/get_all_tickets_for_scan.sql", "eshop_orders/mark_order_and_tickets_paid_internal_v1.sql", "eshop_orders/update_order_and_tickets_to_paid.sql",
         "eshop_orders/recalculate_order_payment_status.sql", "eshop/finalize_ticket_order.sql",
         "eshop_orders/create_ticket_order_client_sync_v1.sql", "eshop_waitlist/commands.sql",
         "eshop_waitlist/accept_offer.sql", "eshop_forms/update_form.sql", "eshop_forms/get_form_by_link.sql",
         "eshop_forms/duplicate_form_to_occasion.sql", "eshop_payment_references/replay.sql",
         "eshop_waitlist/order_overview.sql", "eshop_orders/update_ticket_products_ws.sql",
         "eshop_orders/update_order_and_tickets_to_storno.sql", "eshop_orders/storno_tickets_bulk.sql", "eshop_orders/get_orders.sql", "eshop_orders/get_orders_tab_data.sql", "eshop/get_order_history.sql", "eshop/swap_spot_tickets.sql",
         "eshop/confirm_blueprint_order_change.sql", "emails/email_queue.sql", "eshop/format_occasion_report_text.sql", "eshop/get_report_ws.sql", "eshop_stripe/client_sync.sql", "others/get_app_config.sql"],
    ),
}

def render_source(source):
    body = (ROOT / "database/functions" / source).read_text().rstrip()
    # New private owners must be callable by existing postgres-owned commands.
    # Existing shared functions retain main's owner, including provider-owned
    # scanner definitions which only the migration superuser may replace.
    private_owner = source.startswith("eshop_stripe/") or source == "eshop_transactions/payment_totals.sql"
    return "-- SOURCE: " + source + "\n" + (
        "SET LOCAL ROLE postgres;\n" + body + "\nRESET ROLE;" if private_owner else body
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for filename, (description, sources) in MIGRATIONS.items():
        content = "-- " + description + "\n\n" + "\n\n".join(
            render_source(source) for source in sources
        ) + "\n"
        destination = ROOT / "supabase/migrations" / filename
        if args.check:
            if not destination.exists() or destination.read_text() != content:
                stale.append(filename)
        else:
            destination.write_text(content)
    if stale:
        raise SystemExit("Outdated Stripe migrations: " + ", ".join(stale))
    print("Stripe migration sources match" if args.check else "Assembled 3 unpublished Stripe migrations")

if __name__ == "__main__":
    main()
