#!/usr/bin/env python3
"""Generate the current configuration contract; verify version-aware release parity."""
from pathlib import Path
import json,sys
root=Path(__file__).resolve().parents[1]
spec=json.loads((root/'packages/festapp_contracts/configuration-settings.json').read_text())
client_path=root/'lib/components/unit/unit_settings_fields.dart'
client_contract='// Generated from packages/festapp_contracts/configuration-settings.json.\n// Omission preserves server settings; explicit null clears nullable overrides.\nconst unitSettingsKeys = <String>{\n'+''.join("  '"+key+"',\n" for key in spec['unit'])+'};\n'
contract="-- Generated from packages/festapp_contracts/configuration-settings.json.\nCREATE OR REPLACE FUNCTION public.configuration_settings_contract_internal_v1() RETURNS jsonb\nLANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $contract$\n SELECT $json$"+json.dumps(spec,separators=(',',':'))+"$json$::jsonb;\n$contract$;\nREVOKE ALL ON FUNCTION public.configuration_settings_contract_internal_v1() FROM PUBLIC,anon,authenticated,service_role;\n"
sources=['others/configuration_settings_contract.sql', 'others/configuration_settings.sql', 'user_permissions/game_settings.sql', 'others/save_occasion_domain_command_internal_v1.sql', 'others/save_occasion_client_sync_v1.sql', 'units/update_unit_internal_v1.sql', 'units/save_unit_client_sync_v1.sql', 'others/game_update_settings.sql', 'others/game_update_settings_client_sync_v1.sql', 'others/configuration_authoring.sql', 'others/get_ticket_layout_write_contract_v1.sql']
# The original stage-5 migration is immutable. New contracts are assembled into
# their forward migrations; verify the effective release head, not an old file.
if '--check' in sys.argv:
 if not client_path.exists() or client_path.read_text()!=client_contract:
  raise SystemExit('Unit settings client fields differ from the shared configuration contract')
 if (root/'database/functions/others/configuration_settings_contract.sql').read_text()!=contract:
  raise SystemExit('Current configuration contract differs from its JSON owner')
 from generate_canonical_source_contract import definitions
 effective={}
 for migration in sorted((root/'supabase/migrations').glob('*.sql')):
  for signature,body in definitions(migration.read_text()):
   if isinstance(body,tuple):
    if signature in effective: effective[body[1]]=effective.pop(signature)
   elif body is None: effective.pop(signature,None)
   else: effective[signature]=body
 for name in sources:
  for signature,body in definitions(contract if name.endswith('configuration_settings_contract.sql') else (root/'database/functions'/name).read_text()):
   if body is not None and not isinstance(body,tuple) and effective.get(signature)!=body:
    raise SystemExit('Configuration owner differs from effective migration head: '+signature)
else:
 client_path.write_text(client_contract)
 (root/'database/functions/others/configuration_settings_contract.sql').write_text(contract)
