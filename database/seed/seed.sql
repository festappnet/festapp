DO $$
DECLARE
  org_id bigint;
BEGIN
  SELECT id INTO org_id FROM organizations LIMIT 1;

  IF NOT EXISTS (
    SELECT 1 FROM user_info
    WHERE organization = org_id AND email_readonly = 't@t.com'
  ) THEN
    PERFORM create_user_in_organization_with_data_pure(
      org_id,
      't@t.com',
      'test',
      '{"name": "Michael", "surname": "Testik", "sex": "male"}'::jsonb
    );
  END IF;
END $$;
