#!/usr/bin/env python3
"""Assemble the additive sandbox connector; never rewrite shared history."""
from pathlib import Path
import argparse,json
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args()
m=json.loads((root/'automation/barion-sandbox-migration.json').read_text())
parts=['-- Additive Barion sandbox connector. No credentials, sales activation or jobs.','SET LOCAL ROLE postgres;']
for source in m['sources']: parts.append('-- SOURCE: '+source+'\n'+(root/'database/functions'/source).read_text().rstrip())
parts.append('RESET ROLE;');content='\n\n'.join(parts)+'\n';dest=root/'supabase/migrations'/m['migration']
if args.check:
 if not dest.exists() or dest.read_text()!=content: raise SystemExit('Barion sandbox migration is stale')
 print('Barion sandbox sources match')
else: dest.write_text(content);print('Assembled Barion sandbox migration')
