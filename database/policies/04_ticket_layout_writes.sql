-- Preserve existing column access, while reserving features for occasion save.
-- Do not grant direct writes to roles that did not already have them.
DO $$
DECLARE v_role text; v_columns text; v_update boolean; v_insert boolean;
BEGIN
  SELECT string_agg(quote_ident(attname), ',') INTO v_columns FROM pg_attribute
    WHERE attrelid='public.occasions'::regclass AND attnum>0 AND NOT attisdropped AND attname<>'features';
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    v_update := has_table_privilege(v_role,'public.occasions','UPDATE');
    v_insert := has_table_privilege(v_role,'public.occasions','INSERT');
    EXECUTE format('REVOKE UPDATE, INSERT ON public.occasions FROM %I',v_role);
    EXECUTE format('REVOKE UPDATE(features), INSERT(features) ON public.occasions FROM %I',v_role);
    IF v_update THEN EXECUTE format('GRANT UPDATE (%s) ON public.occasions TO %I',v_columns,v_role); END IF;
    IF v_insert THEN EXECUTE format('GRANT INSERT (%s) ON public.occasions TO %I',v_columns,v_role); END IF;
  END LOOP;
END $$;
