DO $$
DECLARE relation regclass; client_role text;
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
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   PERFORM assert_true(NOT has_table_privilege(client_role,relation,'INSERT,UPDATE,DELETE,TRUNCATE')
     AND NOT has_any_column_privilege(client_role,relation,'INSERT,UPDATE'),
     format('%s cannot bypass commands on %s through table, column or inherited grants',client_role,relation));
  END LOOP;
 END LOOP;
END $$;
