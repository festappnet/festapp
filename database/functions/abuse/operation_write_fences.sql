-- Effective ACL closure for the selected command-owned tables. Preserve SELECT,
-- trusted service grants and definer ownership. Include column and inherited grants.
DO $operation_write_fences$
DECLARE relation regclass; role_name text; column_names text; client_role text;
BEGIN
 FOR relation IN SELECT unnest(ARRAY[
  'eshop.products','eshop.product_types','eshop.product_inventory_contexts',
  'eshop.blueprints','eshop.spots','public.forms','public.form_fields',
  'public.user_group_info','public.user_groups','public.places','public.units',
  'public.user_info','public.occasion_users','public.occasions',
  'public.exclusive_groups','public.exclusive_events','public.news','public.user_news',
  'public.path_groups','public.place_types','public.events','public.event_groups',
  'public.event_roles','public.event_speakers','public.event_users','public.event_users_saved',
  'public.information','public.information_hidden','public.icons'
 ]::regclass[]) LOOP
  SELECT string_agg(quote_ident(attname),',') INTO column_names FROM pg_attribute
   WHERE attrelid=relation AND attnum>0 AND NOT attisdropped;
  EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON TABLE %s FROM PUBLIC',relation);
  EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM PUBLIC',column_names,column_names,relation);
  FOR role_name IN SELECT DISTINCT r.rolname FROM pg_roles r
   WHERE r.rolname IN ('anon','authenticated') OR pg_has_role('anon',r.oid,'MEMBER')
    OR pg_has_role('authenticated',r.oid,'MEMBER') LOOP
   IF role_name IN ('postgres','service_role','authenticator') THEN
    RAISE EXCEPTION 'ordinary role inherits privileged lane: repair role membership explicitly'; END IF;
   EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON TABLE %s FROM %I',relation,role_name);
   EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM %I',column_names,column_names,relation,role_name);
  END LOOP;
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(client_role,relation,'INSERT,UPDATE,DELETE,TRUNCATE')
    OR has_any_column_privilege(client_role,relation,'INSERT,UPDATE') THEN
    RAISE EXCEPTION 'effective command bypass survived: % %',client_role,relation; END IF;
  END LOOP;
 END LOOP;
END $operation_write_fences$;
