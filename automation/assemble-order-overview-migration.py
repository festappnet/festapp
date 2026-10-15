#!/usr/bin/env python3
"""Forward-only overview assembly, independent of the published capacity migration."""
from pathlib import Path
import argparse
root = Path(__file__).resolve().parents[1]
sources = ['order_overview_schema.sql', 'order_overview.sql', 'order_overview_access.sql',
           'order_overview_email.sql', 'offers.sql', 'email_render_context.sql', 'fakturoid_recovery.sql']
content = '-- Customer order overview: read-only capability and durable encrypted sources.\n'
for name in sources:
    source = 'database/functions/eshop_waitlist/' + name
    content += '\n-- Source: ' + source + '\n' + (root / source).read_text() + '\n'
# Only the affected send-time predicate belongs to this migration, not other
# independently evolving queue functions.
queue_source = 'database/functions/emails/email_queue.sql'
queue = (root / queue_source).read_text()
start = queue.index('CREATE OR REPLACE FUNCTION public.email_intent_valid(')
end = queue.index('END $$;', start) + len('END $$;')
content += '\n-- Source: ' + queue_source + ' (email_intent_valid only)\n' + queue[start:end] + '\n'
target = root / 'supabase/migrations/20261015170000_customer_order_overview.sql'
content = content.rstrip() + '\n'
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    if not target.exists() or target.read_text() != content:
        raise SystemExit('Overview migration differs from canonical sources')
    print('Overview migration matches canonical sources')
else:
    target.write_text(content)
    print('Overview migration assembled')
