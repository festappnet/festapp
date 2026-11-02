-- Technical fixture maintenance only. Explicit seed IDs must not collide with
-- subsequent default IDs; consumed sequence values must never be rewound.
DO $$
DECLARE r record; sequence_name text; sequence_value bigint; maximum_id bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE singleton AND project LIKE 'festapp-%') THEN
   RAISE EXCEPTION 'Marked disposable database required for sequence maintenance';
 END IF;
 FOR r IN SELECT table_schema,table_name,column_name FROM information_schema.columns
   WHERE table_schema IN ('public','eshop') AND (column_default LIKE 'nextval%' OR is_identity='YES')
 LOOP
   sequence_name:=pg_get_serial_sequence(format('%I.%I',r.table_schema,r.table_name),r.column_name);
   IF sequence_name IS NULL THEN CONTINUE; END IF;
   EXECUTE format('SELECT last_value FROM %s',sequence_name::regclass) INTO sequence_value;
   EXECUTE format('SELECT COALESCE(max(%I),0) FROM %I.%I',r.column_name,r.table_schema,r.table_name) INTO maximum_id;
   IF maximum_id>=sequence_value THEN PERFORM setval(sequence_name::regclass,maximum_id+1,false); END IF;
 END LOOP;
END $$;
