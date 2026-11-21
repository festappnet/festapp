#!/usr/bin/env python3
"""Emit the catalog migration's read-only audit query for operator preflight."""
from pathlib import Path

from migration_forward_owners import entry_for, render_forward

root = Path(__file__).resolve().parents[1]
migration = entry_for(root, '20261121101000_order_catalog_counts.sql')
path, expected = render_forward(root, migration)
if path.read_text() != expected:
    raise SystemExit('Form catalog migration differs from its registered source')

start = ' -- BEGIN FORM CATALOG PREFLIGHT\n'
end = '\n -- END FORM CATALOG PREFLIGHT'
if expected.count(start) != 1 or expected.count(end) != 1:
    raise SystemExit('Missing or ambiguous form catalog preflight query')
query = expected.split(start, 1)[1].split(end, 1)[0].strip()
print(query + ';')
