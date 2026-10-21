#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "repair-a-registered-embedded-payloads-forward-only" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=repair-a-registered-embedded-payloads-forward-only"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_restore_[0-9]+$ ||
   "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "target database must be postgres or an isolated timestamped rehearsal/restore database"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND v.check_name='a-semantic-reference-repair' AND v.status='pass'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND v.check_name='a-embedded-payload-repair'))")"
[[ "$STATE" == "1|1|0" ]] || fail "target is not the approved pre-repair state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-embedded-payload-repair-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;

CREATE FUNCTION pg_temp.a_mapped_json_id(p_run uuid,p_table text,p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$
DECLARE mapped text;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value)='null' THEN RETURN p_value; END IF;
  SELECT target_id INTO mapped FROM festapp_merge.id_mappings
  WHERE run_id=p_run AND source_table=p_table AND source_id=p_value#>>'{}';
  IF mapped IS NULL THEN RETURN p_value; END IF;
  RETURN to_jsonb(mapped::bigint);
END
$function$;

CREATE FUNCTION pg_temp.a_remap_field_array(p_run uuid,p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$
DECLARE element jsonb; pair record; rebuilt jsonb; result jsonb:='[]'::jsonb; mapped text;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value)<>'array' THEN RETURN p_value; END IF;
  FOR element IN SELECT value FROM jsonb_array_elements(p_value) LOOP
    IF jsonb_typeof(element)<>'object' THEN result:=result||jsonb_build_array(element); CONTINUE; END IF;
    rebuilt:='{}'::jsonb;
    FOR pair IN SELECT key,value FROM jsonb_each(element) LOOP
      mapped:=NULL;
      IF pair.key ~ '^[0-9]+$' THEN
        SELECT target_id INTO mapped FROM festapp_merge.id_mappings
        WHERE run_id=p_run AND source_table='public.form_fields' AND source_id=pair.key;
      END IF;
      rebuilt:=rebuilt||jsonb_build_object(coalesce(mapped,pair.key),pair.value);
    END LOOP;
    result:=result||jsonb_build_array(rebuilt);
  END LOOP;
  RETURN result;
END
$function$;

CREATE FUNCTION pg_temp.a_remap_order_payload(p_run uuid,p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$
DECLARE result jsonb:=p_value; ticket jsonb; product jsonb; field jsonb;
  tickets jsonb:='[]'::jsonb; products jsonb; fields jsonb; input jsonb; input_tickets jsonb;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value)<>'object' THEN RETURN p_value; END IF;
  IF jsonb_typeof(result->'fields')='array' THEN
    result:=jsonb_set(result,'{fields}',pg_temp.a_remap_field_array(p_run,result->'fields'),false);
  END IF;
  IF jsonb_typeof(result->'tickets')='array' THEN
    tickets:='[]'::jsonb;
    FOR ticket IN SELECT value FROM jsonb_array_elements(result->'tickets') LOOP
      IF ticket ? 'id' THEN ticket:=jsonb_set(ticket,'{id}',pg_temp.a_mapped_json_id(p_run,'eshop.tickets',ticket->'id'),false); END IF;
      IF jsonb_typeof(ticket->'products')='array' THEN
        products:='[]'::jsonb;
        FOR product IN SELECT value FROM jsonb_array_elements(ticket->'products') LOOP
          IF product ? 'id' THEN product:=jsonb_set(product,'{id}',pg_temp.a_mapped_json_id(p_run,'eshop.products',product->'id'),false); END IF;
          products:=products||jsonb_build_array(product);
        END LOOP;
        ticket:=jsonb_set(ticket,'{products}',products,false);
      END IF;
      tickets:=tickets||jsonb_build_array(ticket);
    END LOOP;
    result:=jsonb_set(result,'{tickets}',tickets,false);
  END IF;
  IF jsonb_typeof(result->'input_data')='object' THEN
    input:=result->'input_data';
    IF jsonb_typeof(input->'fields')='array' THEN
      input:=jsonb_set(input,'{fields}',pg_temp.a_remap_field_array(p_run,input->'fields'),false);
    END IF;
    IF jsonb_typeof(input->'ticket')='array' THEN
      input_tickets:='[]'::jsonb;
      FOR ticket IN SELECT value FROM jsonb_array_elements(input->'ticket') LOOP
        IF ticket ? 'spot' AND jsonb_typeof(ticket->'spot')<>'null' THEN
          ticket:=jsonb_set(ticket,'{spot}',pg_temp.a_mapped_json_id(p_run,'eshop.spots',ticket->'spot'),false);
        END IF;
        IF jsonb_typeof(ticket->'fields')='array' THEN
          fields:='[]'::jsonb;
          FOR field IN SELECT value FROM jsonb_array_elements(ticket->'fields') LOOP
            IF field ? 'product_type' AND jsonb_typeof(field->'product_type')<>'null' THEN
              field:=jsonb_set(field,'{product_type}',pg_temp.a_mapped_json_id(p_run,'eshop.product_types',field->'product_type'),false);
            END IF;
            fields:=fields||jsonb_build_array(field);
          END LOOP;
          ticket:=jsonb_set(ticket,'{fields}',fields,false);
        END IF;
        input_tickets:=input_tickets||jsonb_build_array(ticket);
      END LOOP;
      input:=jsonb_set(input,'{ticket}',input_tickets,false);
    END IF;
    result:=jsonb_set(result,'{input_data}',input,false);
  END IF;
  RETURN result;
END
$function$;

CREATE FUNCTION pg_temp.a_remap_blueprint_objects(p_run uuid,p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$
DECLARE result jsonb:='[]'::jsonb; element jsonb;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value)<>'array' THEN RETURN p_value; END IF;
  FOR element IN SELECT value FROM jsonb_array_elements(p_value) LOOP
    IF element->>'type'='spot' AND element ? 'id' THEN
      element:=jsonb_set(element,'{id}',pg_temp.a_mapped_json_id(p_run,'eshop.spots',element->'id'),false);
    END IF;
    result:=result||jsonb_build_array(element);
  END LOOP;
  RETURN result;
END
$function$;

DO $repair$
DECLARE import_run uuid; changed_blueprints bigint; changed_orders bigint; changed_history bigint;
  changed_occasion_users bigint; changed_user_news bigint; changed_notifications bigint;
  mapped_blueprint_spot_objects bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='a' AND status='blocked';
  SELECT count(*) INTO mapped_blueprint_spot_objects
  FROM festapp_stage_a_eshop.blueprints source
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(source.objects,'[]'::jsonb)) object(value)
  JOIN festapp_merge.id_mappings mapping ON mapping.run_id=import_run
    AND mapping.source_table='eshop.spots' AND mapping.source_id=object.value->>'id'
  WHERE object.value->>'type'='spot';

  UPDATE eshop.blueprints target SET objects=pg_temp.a_remap_blueprint_objects(import_run,source.objects)
  FROM festapp_stage_a_eshop.blueprints source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.blueprints' AND self.source_id=source.id::text
  WHERE target.id=self.target_id::bigint AND target.objects IS DISTINCT FROM pg_temp.a_remap_blueprint_objects(import_run,source.objects);
  GET DIAGNOSTICS changed_blueprints=ROW_COUNT;

  UPDATE eshop.orders target SET data=pg_temp.a_remap_order_payload(import_run,source.data)
  FROM festapp_stage_a_eshop.orders source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.orders' AND self.source_id=source.id::text
  WHERE target.id=self.target_id::bigint AND target.data IS DISTINCT FROM pg_temp.a_remap_order_payload(import_run,source.data);
  GET DIAGNOSTICS changed_orders=ROW_COUNT;

  UPDATE eshop.orders_history target SET data=pg_temp.a_remap_order_payload(import_run,source.data)
  FROM festapp_stage_a_eshop.orders_history source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.orders_history' AND self.source_id=source.id::text
  WHERE target.id=self.target_id::bigint AND target.data IS DISTINCT FROM pg_temp.a_remap_order_payload(import_run,source.data);
  GET DIAGNOSTICS changed_history=ROW_COUNT;

  UPDATE public.occasion_users target SET "user"=mapping.target_id::uuid
  FROM festapp_stage_a_public.occasion_users source
  JOIN festapp_merge.id_mappings occasion_map ON occasion_map.run_id=import_run
    AND occasion_map.source_table='public.occasions' AND occasion_map.source_id=source.occasion::text
  JOIN festapp_merge.id_mappings mapping ON mapping.run_id=import_run
    AND mapping.source_table='auth.users' AND mapping.source_id=source."user"::text
  WHERE target.occasion=occasion_map.target_id::bigint AND target."user"=source."user";
  GET DIAGNOSTICS changed_occasion_users=ROW_COUNT;
  UPDATE public.user_news target SET "user"=mapping.target_id::uuid
  FROM festapp_stage_a_public.user_news source
  JOIN festapp_merge.id_mappings news_map ON news_map.run_id=import_run
    AND news_map.source_table='public.news' AND news_map.source_id=source.news_id::text
  JOIN festapp_merge.id_mappings mapping ON mapping.run_id=import_run
    AND mapping.source_table='auth.users' AND mapping.source_id=source."user"::text
  WHERE target.news_id=news_map.target_id::bigint AND target."user"=source."user";
  GET DIAGNOSTICS changed_user_news=ROW_COUNT;
  UPDATE public.log_notifications target SET user_id=mapping.target_id::uuid
  FROM festapp_stage_a_public.log_notifications source
  JOIN festapp_merge.id_mappings mapping ON mapping.run_id=import_run
    AND mapping.source_table='auth.users' AND mapping.source_id=source.user_id::text
  WHERE target.id=source.id AND target.user_id=source.user_id;
  GET DIAGNOSTICS changed_notifications=ROW_COUNT;

  IF EXISTS (SELECT 1 FROM festapp_stage_a_eshop.blueprints source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.blueprints' AND self.source_id=source.id::text
    JOIN eshop.blueprints target ON target.id=self.target_id::bigint
    WHERE target.objects IS DISTINCT FROM pg_temp.a_remap_blueprint_objects(import_run,source.objects))
  THEN RAISE EXCEPTION 'blueprint payload repair did not converge'; END IF;
  IF EXISTS (SELECT 1 FROM festapp_stage_a_eshop.orders source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.orders' AND self.source_id=source.id::text
    JOIN eshop.orders target ON target.id=self.target_id::bigint
    WHERE target.data IS DISTINCT FROM pg_temp.a_remap_order_payload(import_run,source.data))
  THEN RAISE EXCEPTION 'order payload repair did not converge'; END IF;
  IF EXISTS (SELECT 1 FROM festapp_stage_a_eshop.orders_history source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.orders_history' AND self.source_id=source.id::text
    JOIN eshop.orders_history target ON target.id=self.target_id::bigint
    WHERE target.data IS DISTINCT FROM pg_temp.a_remap_order_payload(import_run,source.data))
  THEN RAISE EXCEPTION 'order-history payload repair did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.occasion_users source
    JOIN festapp_merge.id_mappings occasion_map ON occasion_map.run_id=import_run
      AND occasion_map.source_table='public.occasions' AND occasion_map.source_id=source.occasion::text
    LEFT JOIN festapp_merge.id_mappings user_map ON user_map.run_id=import_run
      AND user_map.source_table='auth.users' AND user_map.source_id=source."user"::text
    WHERE NOT EXISTS (SELECT 1 FROM public.occasion_users target
      WHERE target.occasion=occasion_map.target_id::bigint
        AND target."user"=coalesce(user_map.target_id::uuid,source."user"))
  ) THEN RAISE EXCEPTION 'source-a occasion-user references did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.user_news source
    JOIN festapp_merge.id_mappings news_map ON news_map.run_id=import_run
      AND news_map.source_table='public.news' AND news_map.source_id=source.news_id::text
    LEFT JOIN festapp_merge.id_mappings user_map ON user_map.run_id=import_run
      AND user_map.source_table='auth.users' AND user_map.source_id=source."user"::text
    WHERE NOT EXISTS (SELECT 1 FROM public.user_news target
      WHERE target.news_id=news_map.target_id::bigint
        AND target."user"=coalesce(user_map.target_id::uuid,source."user"))
  ) THEN RAISE EXCEPTION 'source-a user-news references did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.log_notifications source
    LEFT JOIN festapp_merge.id_mappings user_map ON user_map.run_id=import_run
      AND user_map.source_table='auth.users' AND user_map.source_id=source.user_id::text
    JOIN public.log_notifications target ON target.id=source.id
    WHERE target.user_id IS DISTINCT FROM coalesce(user_map.target_id::uuid,source.user_id)
  ) THEN RAISE EXCEPTION 'source-a notification-user references did not converge'; END IF;

  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,'a-embedded-payload-repair','pass',jsonb_build_object(
      'changed_blueprints',changed_blueprints,'changed_orders',changed_orders,
      'changed_order_history',changed_history,'changed_occasion_users',changed_occasion_users,
      'changed_user_news',changed_user_news,'changed_notifications',changed_notifications,
      'mapped_blueprint_spot_objects',mapped_blueprint_spot_objects,'retained_unmapped_historical_snapshot_ids',true,
      'strategy','registered-embedded-payload-repair-v1','deleted_rows',0));
END
$repair$;

COMMIT;
SQL

psql_main -Atqc "SELECT observed FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id)
WHERE r.source_alias='a' AND v.check_name='a-embedded-payload-repair'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Registered source-a embedded payloads repaired forward-only; nothing was deleted."
echo "Evidence: $RUN_DIR"
