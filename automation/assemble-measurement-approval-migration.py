#!/usr/bin/env python3
"""Preserve the historical snapshot; current owners ship in the unification migration."""
import hashlib
from pathlib import Path
import sys
TARGET = Path(__file__).resolve().parents[1] / 'supabase/migrations/20261110190000_unit_measurement_approval_request.sql'
if '--check' not in sys.argv:
    raise SystemExit('Historical migration is immutable; use assemble-measurement-unification-migration.py')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != 'ec9dbd35f2ec04368453c1c653131ff19d19c0efb5eefda6dd739361fd1e6a46':
    raise SystemExit('Historical measurement migration changed')
