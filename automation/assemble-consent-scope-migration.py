#!/usr/bin/env python3
"""Preserve the applied semantic scope snapshot; use the website binding forward assembler."""
import hashlib
from pathlib import Path
import sys
TARGET=Path(__file__).resolve().parents[1]/'supabase/migrations/20261111120000_form_consent_scope.sql'
if '--check' not in sys.argv:
 raise SystemExit('Historical migration is immutable; use assemble-website-consent-bindings-migration.py')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != '7757303f27b732efaddc8a1a862872a788d916499266dd510509aeccef2c8f4c':
 raise SystemExit('Historical consent scope migration changed')
