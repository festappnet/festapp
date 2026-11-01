BEGIN;
DO $$ BEGIN
 IF NOT has_table_privilege('service_role','public.form_seating_transitions','SELECT') THEN
  RAISE EXCEPTION 'email preparation cannot read seating transitions';
 END IF;
 IF has_table_privilege('anon','public.form_seating_transitions','SELECT')
 OR has_table_privilege('authenticated','public.form_seating_transitions','SELECT')
 OR has_table_privilege('service_role','public.form_seating_transitions','INSERT')
 OR has_table_privilege('service_role','public.form_seating_transitions','UPDATE')
 OR has_table_privilege('service_role','public.form_seating_transitions','DELETE') THEN
  RAISE EXCEPTION 'seating transitions unexpectedly accessible';
 END IF;
END $$;
ROLLBACK;
