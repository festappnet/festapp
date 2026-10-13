#!/usr/bin/env python3
"""Assemble the scoped forward tone correction without rewriting published SQL."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    'database/functions/eshop_waitlist/email_render_context.sql',
    'database/functions/eshop_waitlist/email_preview.sql',
    'database/functions/eshop_waitlist/email_templates.sql',
]
TARGET = ROOT / 'supabase/migrations/20261014000100_waitlist_email_communication_tone.sql'
content = '-- Waitlist emails inherit the existing effective form communication tone.\n'
for source in SOURCES:
    content += '\n-- Source: ' + source + '\n' + (ROOT / source).read_text() + '\n'
TARGET.write_text(content.rstrip() + '\n')
print('Waitlist email-tone forward migration assembled')
