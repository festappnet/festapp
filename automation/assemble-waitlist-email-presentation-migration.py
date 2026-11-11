#!/usr/bin/env python3
"""Assemble forward count-aware waitlist presentation without changing published SQL."""
import migration_inputs
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    'database/functions/eshop_waitlist/email_render_context.sql',
    'database/functions/eshop_waitlist/email_preview.sql',
    'database/functions/eshop_waitlist/capabilities.sql',
]
TARGET = ROOT / 'supabase/migrations/20261014000200_waitlist_email_offer_presentation.sql'
content = '-- Count-aware waitlist instructions and shared authoritative display timezone.\n'
for source in SOURCES:
    content += '\n-- Source: ' + source + '\n' + migration_inputs.read_text(ROOT / source) + '\n'
migration_inputs.write_text(TARGET, content.rstrip() + '\n')
print('Waitlist presentation forward migration assembled')
