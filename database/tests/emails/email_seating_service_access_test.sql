DO $$ BEGIN
 IF to_regclass('public.form_seating_transitions') IS NOT NULL THEN
   RAISE EXCEPTION 'retired seating publication state remains';
 END IF;
 IF NOT has_table_privilege('service_role','public.forms','SELECT') THEN
   RAISE EXCEPTION 'email preparation cannot read the saved form binding';
 END IF;
 IF to_regprocedure('public.seating_admissions_internal(bigint)') IS NULL THEN
   RAISE EXCEPTION 'canonical form seating projection is missing';
 END IF;
END $$;
