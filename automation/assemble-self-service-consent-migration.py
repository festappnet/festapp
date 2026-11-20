#!/usr/bin/env python3
"""Verify the applied self-service consent snapshot; email_intent_valid moved to the Meta CAPI request forward."""
import hashlib
from pathlib import Path
import sys
from generate_canonical_source_contract import render, TARGET as PARITY
TARGET = Path(__file__).resolve().parents[1] / 'supabase/migrations/20261117160000_self_service_website_consent.sql'
if '--check' not in sys.argv:
    raise SystemExit('Applied migration is immutable; use the registered forward in automation/migration-forward-owners.json')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != '69318fe6f671b5e4f022a6b209733a22915952d97b8a3fb1035fe33224f5b338':
    raise SystemExit('Applied self-service consent migration changed')
if PARITY.read_text() != render():
    raise SystemExit('Canonical source parity is stale')
print('Self-service consent migration and source parity verified')
