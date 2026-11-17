#!/usr/bin/env python3
"""Verify the applied request lifecycle snapshot; use the self-service forward."""
import hashlib
from pathlib import Path
import sys
TARGET = Path(__file__).resolve().parents[1] / 'supabase/migrations/20261111160000_measurement_request_lifecycle.sql'
if '--check' not in sys.argv:
    raise SystemExit('Applied migration is immutable; use assemble-self-service-consent-migration.py')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != '64c4d4ec931010584fcab866baa30494352434e4fbce836bf3bacbe2a8ef985e':
    raise SystemExit('Applied measurement request lifecycle migration changed')
