#!/usr/bin/env python3
"""Preserve the historical snapshot; current owners ship in the unification migration."""
import hashlib
from pathlib import Path
import sys
TARGET = Path(__file__).resolve().parents[1] / 'supabase/migrations/20261110200000_form_measurement_consent_bridge.sql'
if '--check' not in sys.argv:
    raise SystemExit('Historical migration is immutable; use assemble-measurement-unification-migration.py')
if hashlib.sha256(TARGET.read_bytes()).hexdigest() != '818f1c383af8fcfede196df39c13d55a887134f35fc8429ff409cde700ec2879':
    raise SystemExit('Historical measurement migration changed')
