"""Reconstruct the exact pre-policy function owners inside an isolated upgrade clone."""
import json
import re
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'automation'))
from generate_canonical_source_contract import definitions, statements
manifest = json.loads((ROOT / 'automation/payment-method-policy-migration.json').read_text())
baseline = json.loads((ROOT / 'supabase/baseline/manifest.json').read_text())
prior = {}
inputs = [ROOT / baseline['schema']['path']]
inputs += sorted(p for p in (ROOT / 'supabase/migrations').glob('*.sql') if baseline['coveredThrough'] < p.name[:14] < '20261112160000')
for path in inputs:
    for statement in statements(path.read_text()):
        for signature, body in definitions(statement):
            if body is None:
                prior.pop(signature, None)
            elif not isinstance(body, tuple):
                prior[signature] = statement
changed = set()
policy_sources=set(manifest['sources'])
for extra in ['payment-policy-refinement-migration.json','payment-policy-release-integration-migration.json']:
    extra_path=ROOT/'automation'/extra
    if extra_path.exists(): policy_sources.update(json.loads(extra_path.read_text())['sources'])
for source in sorted(policy_sources):
    changed.update(sig for sig, body in definitions((ROOT / 'database/functions' / source).read_text()))
print('''CREATE TABLE eshop.stripe_unit_features (
 unit_id bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT false,updated_at timestamptz NOT NULL DEFAULT now(),updated_by uuid);
ALTER TABLE eshop.stripe_unit_features ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_unit_features FROM PUBLIC,anon,authenticated,service_role;
''')
print('DROP TRIGGER IF EXISTS payment_template_policy_fence ON public.email_templates; DROP TRIGGER IF EXISTS payment_template_policy_fence ON public.email_wrappers;')
for signature in sorted(changed - prior.keys()):
    print('DROP FUNCTION IF EXISTS ' + signature + ' RESTRICT;')
for signature in sorted(changed & prior.keys()):
    print(re.sub(r'\bCREATE\s+FUNCTION\b', 'CREATE OR REPLACE FUNCTION', prior[signature], count=1, flags=re.I))
# These are solely new policy configuration/audit records, never a money ledger.
print('''DROP TABLE eshop.payment_template_epochs,eshop.payment_template_reviews,eshop.payment_method_policy_commands,
 eshop.payment_method_policy_unit_preferences,eshop.unit_payment_method_policies,
 eshop.organization_payment_method_policies,eshop.payment_method_policy_scopes RESTRICT;
ALTER TABLE eshop.payment_providers DROP COLUMN refund_write_supported,
 DROP COLUMN partial_refund_supported,DROP COLUMN refund_observation_supported;
''')
