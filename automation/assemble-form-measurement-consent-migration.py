#!/usr/bin/env python3
"""Forward-only current measurement policy. Historical migrations stay immutable."""
import migration_inputs
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
SOURCES=['eshop_forms/form_measurement_policy.sql']
TARGET=ROOT/'supabase/migrations/20261107170000_form_measurement_protocol.sql'
import hashlib
if '--check' in sys.argv:
 if hashlib.sha256(migration_inputs.read_bytes(TARGET)).hexdigest() != 'd3848746f2d13380301b89e2a48ba05727f906e9506d620fe8f01d5316fddfa4':
  raise SystemExit('Applied consent migration changed')
else:
 raise SystemExit('Applied consent migration is immutable; use the consent bridge forward assembler')
