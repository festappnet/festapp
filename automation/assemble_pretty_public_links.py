#!/usr/bin/env python3
"""Reassemble pretty public links migration from its canonical source markers."""
import migration_inputs
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
MIGRATION = ROOT / "supabase/migrations/20261015200000_pretty_public_links.sql"
text = migration_inputs.read_text(MIGRATION)
header = text[:text.index("\n-- Source:")]
trailer = text[text.index("\n-- Close abandoned"):]
sources = re.findall(r"^-- Source: (database/functions/[^\n]+)$", text, re.M)
if len(sources) != len(set(sources)):
    raise SystemExit("Duplicate canonical source marker")
migration_inputs.write_text(MIGRATION, header + "".join(
    "\n-- Source: " + source + "\n" + (ROOT / source).read_text() + "\n"
    for source in sources
) + trailer)
