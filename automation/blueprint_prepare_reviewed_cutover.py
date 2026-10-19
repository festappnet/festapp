#!/usr/bin/env python3
"""Prepare a private, atomic administrative cutover without impersonating users.

Only reviewed initial geometry/bindings are installed. No commercial row is
updated. Runtime RPC authorization and demo write protection remain unchanged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--converted', required=True)
p.add_argument('--fonts', required=True)
p.add_argument('--organization', type=int, required=True)
p.add_argument('--expected-count', type=int, required=True)
p.add_argument('--output', required=True)
p.add_argument('--database', default='festapp_rehearsal_20260909220601')
a = p.parse_args()
assert a.database.replace('_', '').isalnum(), 'invalid database assertion'
raw = Path(a.converted).read_bytes()
rows = [b for b in json.loads(raw)['blueprints'] if b['organizationId'] == a.organization]
assert len(rows) == a.expected_count and rows, 'reviewed scope count mismatch'
assert len({b['blueprintId'] for b in rows}) == len(rows), 'duplicate blueprint'
for b in rows:
    assert hashlib.sha256(b['reviewedSourceText'].encode()).hexdigest() == b['sourceSha256']
    source = json.loads(b['reviewedSourceText'])
    assert source['id'] == b['blueprintId'] == b['request']['id']
    assert source['occasion'] == b['occasionId'] == b['request']['occasion']
    assert source['organization'] == a.organization == b['request']['organization']
    assert not b['request']['areaBindingChanges'] and not b['request']['layout']['selectionUnits']
    assert b['request']['expected_layout_revision'] == 0
    assert not b['request']['layout'].get('background'), 'native-only reviewed cutover required'
fonts = json.loads(Path(a.fonts).read_text())['fonts']
payload = json.dumps(rows, separators=(',', ':'), ensure_ascii=False)
font_payload = json.dumps(fonts, separators=(',', ':'), ensure_ascii=False)
assert '$reviewed$' not in payload and '$fonts$' not in font_payload
sha = hashlib.sha256(payload.encode()).hexdigest()
version = '20261019236200'
sql = """BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
DO $cutover$
DECLARE batch jsonb:=$reviewed$PAYLOAD$reviewed$::jsonb; fonts jsonb:=$fonts$FONTS$fonts$::jsonb;
 entry jsonb; req jsonb; source jsonb; change jsonb; row eshop.blueprints; spot eshop.spots;
 ids bigint[]; before_spots jsonb; expected_group uuid; original_group text; font_id text;
BEGIN
 IF current_database()<>'DATABASE_ASSERTION' OR session_user<>'postgres' THEN
  RAISE EXCEPTION 'canonical administrative database session required'; END IF;
 SELECT array_agg((b->>'occasionId')::bigint ORDER BY (b->>'occasionId')::bigint) INTO ids FROM jsonb_array_elements(batch) b;
 PERFORM public.lock_blueprint_scope_internal(ids);
 PERFORM 1 FROM eshop.blueprints WHERE id IN(SELECT (b->>'blueprintId')::bigint FROM jsonb_array_elements(batch) b) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.products WHERE occasion=ANY(ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE occasion=ANY(ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.id),'[]') INTO before_spots FROM eshop.spots s WHERE s.occasion=ANY(ids);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 FOR font_id IN SELECT jsonb_object_keys(fonts) LOOP
  PERFORM public.register_blueprint_layout_font(font_id,fonts->font_id);
 END LOOP;
 PERFORM set_config('request.jwt.claim.role','',true);
 FOR entry IN SELECT * FROM jsonb_array_elements(batch) LOOP
  req:=entry->'request';source:=(entry->>'reviewedSourceText')::jsonb;
  SELECT * INTO STRICT row FROM eshop.blueprints WHERE id=(entry->>'blueprintId')::bigint;
  IF row.organization<>ORGANIZATION OR row.occasion<>(entry->>'occasionId')::bigint OR
   public.blueprint_legacy_migration_source_internal(row.id) IS DISTINCT FROM source OR
   encode(extensions.digest(convert_to(entry->>'reviewedSourceText','UTF8'),'sha256'),'hex') IS DISTINCT FROM entry->>'sourceSha256' THEN
    RAISE EXCEPTION 'reviewed source changed for blueprint %',row.id; END IF;
  IF row.layout IS NOT NULL THEN RAISE EXCEPTION 'initial layout required for blueprint %',row.id; END IF;
  IF row.layout_revision<>0 OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=row.id) OR
   jsonb_array_length(req->'seatChanges')<>(SELECT count(*) FROM eshop.spots WHERE blueprint=row.id) OR
   jsonb_array_length(req->'areaBindingChanges')<>0 OR jsonb_array_length(req#>'{layout,selectionUnits}')<>0 THEN
    RAISE EXCEPTION 'initial binding set mismatch for blueprint %',row.id; END IF;
  PERFORM public.validate_blueprint_layout_internal(req->'layout');
  PERFORM public.check_blueprint_image_resource_internal(req->'layout',row.occasion);
  FOR change IN SELECT * FROM jsonb_array_elements(req->'seatChanges') LOOP
   SELECT * INTO STRICT spot FROM eshop.spots WHERE id=(change->>'spotId')::bigint AND blueprint=row.id;
   SELECT obj->>'group' INTO original_group FROM jsonb_array_elements(coalesce(row.objects,'[]')) obj WHERE obj->>'type'='spot' AND (obj->>'id')::bigint=spot.id;
   IF NOT FOUND THEN RAISE EXCEPTION 'missing archival seat'; END IF;
   expected_group:=NULL;
   IF original_group IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(row.groups,'[]')) g WHERE g->>'id'=original_group) THEN
    expected_group:=extensions.uuid_generate_v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',format('festapp:occasion:%s:blueprint:%s:group:%s',row.occasion,row.id,original_group)); END IF;
   IF change->>'operation' IS DISTINCT FROM 'upsert' OR change->>'selectionUnitId' IS NOT NULL OR
    (change->>'productId')::bigint IS DISTINCT FROM spot.product OR change->>'title' IS DISTINCT FROM coalesce(spot.title,'') OR
    (change->>'blocked')::boolean IS DISTINCT FROM coalesce(spot.state='black',false) OR
    (change->>'groupNodeId')::uuid IS DISTINCT FROM expected_group OR
    (change->>'nodeId')::uuid IS DISTINCT FROM extensions.uuid_generate_v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',format('festapp:occasion:%s:blueprint:%s:spot:%s',row.occasion,row.id,spot.id)) OR
    NOT EXISTS(SELECT 1 FROM jsonb_array_elements(req#>'{layout,nodes}') n WHERE n->>'kind'='seat' AND n->>'id'=change->>'nodeId') THEN
     RAISE EXCEPTION 'reviewed seat identity/facts mismatch for blueprint %',row.id; END IF;
   INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
    VALUES(row.id,(change->>'nodeId')::uuid,spot.id,NULL,expected_group,(change->>'blocked')::boolean);
  END LOOP;
  FOR change IN SELECT * FROM jsonb_array_elements(req->'groupProductChanges') LOOP
   IF NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=(change->>'productId')::bigint AND occasion=row.occasion) OR
    NOT EXISTS(SELECT 1 FROM jsonb_array_elements(req#>'{layout,nodes}') n WHERE n->>'id'=change->>'groupNodeId' AND n->>'kind'='group') THEN
     RAISE EXCEPTION 'invalid reviewed group product'; END IF;
   INSERT INTO eshop.blueprint_group_products(blueprint,group_node,product) VALUES(row.id,(change->>'groupNodeId')::uuid,(change->>'productId')::bigint);
  END LOOP;
  UPDATE eshop.blueprints SET layout=req->'layout',layout_revision=1,updated_at=now() WHERE id=row.id;
 END LOOP;
 IF before_spots IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.id),'[]') FROM eshop.spots s WHERE s.occasion=ANY(ids)) THEN
  RAISE EXCEPTION 'commercial rows changed'; END IF;
 IF (SELECT count(*) FROM eshop.blueprints WHERE organization=ORGANIZATION AND layout IS NOT NULL)<>EXPECTED_COUNT THEN
  RAISE EXCEPTION 'converted scope count mismatch'; END IF;
 INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('VERSION','blueprint_reviewed_organization_ORGANIZATION',ARRAY['Reviewed administrative native geometry cutover; organization ORGANIZATION; count EXPECTED_COUNT; payload SHA256 DIGEST']);
END $cutover$;
NOTIFY pgrst,'reload schema';
COMMIT;
"""
for key, value in [('DATABASE_ASSERTION', a.database), ('PAYLOAD', payload), ('FONTS', font_payload), ('ORGANIZATION', str(a.organization)), ('EXPECTED_COUNT', str(a.expected_count)), ('VERSION', version), ('DIGEST', sha)]:
    sql = sql.replace(key, value)
output = Path(a.output)
with os.fdopen(os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
    f.write(sql)
print(f'Prepared {len(rows)} reviewed native layouts; payload SHA256 {sha}')
