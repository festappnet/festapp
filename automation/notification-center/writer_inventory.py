#!/usr/bin/env python3
"""Bounded static candidate inventory; not a claim of semantic writer coverage."""
import json
import re
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'automation'))
from generate_canonical_source_contract import definitions, statements
TARGETS = r'(?:public\.)?(?:organization_users|occasion_users|user_info|notification_center_events|email_messages)|eshop\.orders'
pattern = re.compile(r'\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+('+TARGETS+r')\b',re.I)
rows=[]
for path in sorted((ROOT/'database/functions').rglob('*.sql')):
    created='\n'.join(s for s in statements(path.read_text()) if re.search(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION',s,re.I))
    for signature,body in definitions(created):
        if not isinstance(body,str):
            continue
        relations=sorted({m.group(1).lower() for m in pattern.finditer(body)})
        if relations:
            rows.append({'source':path.relative_to(ROOT).as_posix(),'function':signature,'relations':relations})
result={'method':'Static mutation candidates in canonical SQL; retained/overwritten definitions, dynamic SQL, indirect callers, external service writes and grants require semantic review.', 'writers':rows}
print(json.dumps(result,indent=2))
