#!/usr/bin/env python3
"""Verify the immutable website proposal migration; later forwards own its sources."""
import hashlib
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'supabase/migrations/20261111150000_measurement_websites.sql'
if '--check' not in sys.argv:
    raise SystemExit('Website proposal migration is immutable; author a scoped forward migration')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != '7aa2b0296e2b3281f1a8fac3e98535378ed61a31733d1ad1c447c44d4c935d7b':
    raise SystemExit('Website proposal migration bytes changed')
