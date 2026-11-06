#!/usr/bin/env python3
"""Verify frozen Stripe migration history; new changes use forward migrations."""
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
    history = json.loads((ROOT / "automation/stripe-migration-history.json").read_text())
    for filename, digest in history.items():
        if hashlib.sha256((ROOT / "supabase/migrations" / filename).read_bytes()).hexdigest() != digest:
            raise SystemExit("Changed frozen Stripe migration: " + filename)
    print("Stripe migration history unchanged")
if __name__ == "__main__":
    main()
