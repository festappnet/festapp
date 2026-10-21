#!/usr/bin/env python3
"""Index assertions in the explicitly reviewed 2048-role contract, not textual coverage."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FOLDER=ROOT/'docs/plans/evidence/canonical-authorization-20261020'
source=ROOT/'tools/festapp/test/canonical-authorization-postgres.test.mjs'
text=source.read_text();start=text.index("test('canonical truth table preserves server operation rights across 2048 role combinations'")
end=text.index("test('projection travels",start);block=text[start:end]
# Only the single result object compared by assert.deepEqual(r,{...}) is indexed.
query=block[block.index('const r=(await db.query('):block.index('assert.deepEqual(r,')]
assert 'for(let bits=0;bits<2048;bits++)' in block
assert 'unchanged context envelope, roles ${bits}' in block
names=set(re.findall(r'\b((?:can_|get_can_)[a-z0-9_]+)\s*\(',query))
catalog=json.loads((FOLDER/'catalog-after.json').read_text())
proof=[]
for f in catalog['functions']:
 if f['signature'].split('(')[0] in names:
  proof.append(dict(signature=f['signature'],bodyMd5=f['bodyMd5'],state='role-truth-table-tested',
   actor='Authenticated JWT actor; synthetic occasion/unit/tenant membership combinations',
   resource='Actual synthetic occasion, its owning unit and tenant; no caller-provided role claims',
   contract='All 2048 combinations asserted against an explicit expected result object; capability projection and original context envelope also compared',
   test=str(source.relative_to(ROOT)),testName='canonical truth table preserves server operation rights across 2048 role combinations',
   log='/tmp/festapp-authz-full-final.log',
   limits='This result alone does not prove each downstream writer, concurrent mutation, service lane, anonymous path or historical adapter.'))
result=dict(state='executed predicate truth-table evidence; full boundary classification is in domain-ledger.json',
 testBlockSha256=hashlib.sha256(block.encode()).hexdigest(),
 logSha256=hashlib.sha256(Path('/tmp/festapp-authz-full-final.log').read_bytes()).hexdigest(),functions=proof)
(FOLDER/'semantic-contract-evidence.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'Indexed {len(proof)} explicitly asserted operation predicates; downstream closure remains separate.')
