-- Standalone containment. No data writes, runtime dependency or history rewrite.
DO $$
DECLARE signature text;
BEGIN
  FOREACH signature IN ARRAY ARRAY['public.migrate_users_to_org(bigint)',
    'public.update_spot(jsonb)', 'public.apply_allocations_claim_only(bigint)'] LOOP
    IF to_regprocedure(signature) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', signature);
    END IF;
  END LOOP;
END $$;
