BEGIN;

-- Slugs are globally reserved. Resolving an alias must retain tenant checks,
-- and a different tenant cannot claim either a current or historical slug.
DO $$
DECLARE
  v_user uuid;
  v_foreign_org bigint;
  v_own_org bigint;
  v_foreign_unit bigint;
  v_own_unit bigint;
  v_foreign_occasion bigint;
  v_own_occasion bigint;
  v_result jsonb;
  v_link text := 'duplicate-edit-' || gen_random_uuid()::text;
BEGIN
  PERFORM create_user_for_test('occasion_edit_tenant_user',
    'occasion-edit-tenant@test.local');
  v_user := get_user_id('occasion_edit_tenant_user');

  INSERT INTO public.organizations (title)
  VALUES ('Foreign occasion edit test organization')
  RETURNING id INTO v_foreign_org;
  INSERT INTO public.organizations (title)
  VALUES ('Own occasion edit test organization')
  RETURNING id INTO v_own_org;

  UPDATE public.user_info SET organization = v_own_org WHERE id = v_user;

  INSERT INTO public.units (title, organization)
  VALUES ('Foreign occasion edit test unit', v_foreign_org)
  RETURNING id INTO v_foreign_unit;
  INSERT INTO public.units (title, organization)
  VALUES ('Own occasion edit test unit', v_own_org)
  RETURNING id INTO v_own_unit;

  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Foreign duplicate occasion', v_link || '-foreign', now(), now() + interval '1 day',
      v_foreign_org, v_foreign_unit)
  RETURNING id INTO v_foreign_occasion;
  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Own duplicate occasion', v_link, now(), now() + interval '1 day',
      v_own_org, v_own_unit)
  RETURNING id INTO v_own_occasion;

  PERFORM public.reserve_public_link_internal('occasion',v_foreign_occasion,v_link || '-foreign',true);
  PERFORM public.reserve_public_link_internal('occasion',v_own_occasion,v_link,true);
  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',v_own_occasion,v_link || '-current') WHERE id=v_own_occasion;

  INSERT INTO public.occasion_users
    (occasion, "user", is_manager, is_editor_view)
  VALUES (v_own_occasion, v_user, true, true);

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_result := public.get_occasion_for_edit_v1(v_link);

  PERFORM assert_eq(
    (v_result->>'id')::bigint,
    v_own_occasion,
    'occasion edit reader resolves historical alias inside the caller organization'
  );
  PERFORM assert_true(
    (v_result->>'id')::bigint <> v_foreign_occasion,
    'occasion edit reader never returns the foreign duplicate'
  );
  BEGIN
    PERFORM public.get_occasion_for_edit_v1(v_link || '-foreign');
    RAISE EXCEPTION 'Foreign alias accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.reserve_public_link_internal('occasion',v_own_occasion,v_link || '-foreign');
    RAISE EXCEPTION 'Foreign reservation stolen';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END
$$ LANGUAGE plpgsql;

ROLLBACK;
