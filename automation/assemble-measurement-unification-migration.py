#!/usr/bin/env python3
"""Verify the immutable measurement runtime-support migration."""
import hashlib
from pathlib import Path
import sys
TARGET = Path(__file__).resolve().parents[1] / 'supabase/migrations/20261110210000_measurement_runtime_support.sql'
if '--check' not in sys.argv:
    raise SystemExit('Historical migration is immutable; use assemble-consent-scope-migration.py')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != 'de01619f2b98f0353ec6eff0c4cb23aa4c6c09689d0a33ca3c6dff2107cdcc18':
    raise SystemExit('Historical measurement runtime-support migration changed')
