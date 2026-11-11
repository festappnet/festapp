#!/usr/bin/env python3
"""Verify frozen Stripe migration history; new changes use forward migrations."""
import migration_inputs
from pathlib import Path
import argparse
import hashlib
import json
ROOT = Path(__file__).resolve().parents[1]
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not args.check:
        raise SystemExit("Stripe migrations are frozen. Use automation/assemble-payment-provider-migration.py for the connector cutover.")
    history = json.loads(migration_inputs.read_text(ROOT / "automation/stripe-migration-history.json"))
    for filename, digest in history.items():
        if hashlib.sha256(migration_inputs.read_bytes(ROOT / "supabase/migrations" / filename)).hexdigest() != digest:
            raise SystemExit("Changed frozen Stripe migration: " + filename)
    print("Stripe migration history unchanged")
if __name__ == "__main__":
    main()
