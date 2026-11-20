BEGIN;

DO $$
DECLARE
  owner_id uuid := gen_random_uuid();
  other_id uuid := gen_random_uuid();
  org bigint;
  first_unit bigint;
  second_unit bigint;
  hidden_unit bigint;
  event_id bigint;
BEGIN
  INSERT INTO public.organizations(title) VALUES ('Favorite fixture') RETURNING id INTO org;
  INSERT INTO auth.users(id) VALUES (owner_id), (other_id);
  INSERT INTO public.user_info(id, organization) VALUES (owner_id, org), (other_id, org);
  INSERT INTO public.units(title, organization) VALUES ('First', org) RETURNING id INTO first_unit;
  INSERT INTO public.units(title, organization) VALUES ('Second', org) RETURNING id INTO second_unit;
  INSERT INTO public.units(title, organization) VALUES ('Restricted', org) RETURNING id INTO hidden_unit;
  INSERT INTO public.unit_users(unit, "user", is_editor_view)
    VALUES (first_unit, owner_id, true), (first_unit, other_id, true);
  INSERT INTO public.occasions(title, organization, unit, link, start_time, end_time)
    VALUES ('Second event', org, second_unit, gen_random_uuid()::text, now(), now() + interval '1 hour') RETURNING id INTO event_id;
  INSERT INTO public.occasion_users(occasion, "user", is_editor_order_view)
    VALUES (event_id, owner_id, true);

  IF has_table_privilege('anon', 'public.unit_picker_favorites', 'SELECT,INSERT,DELETE') THEN
    RAISE EXCEPTION 'Anonymous access to favorites';
  END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', owner_id::text, true);
  INSERT INTO public.unit_picker_favorites VALUES (owner_id, first_unit), (owner_id, second_unit);
  INSERT INTO public.unit_picker_favorites VALUES (owner_id, first_unit) ON CONFLICT DO NOTHING;
  IF (SELECT count(*) FROM public.unit_picker_favorites) <> 2 THEN
    RAISE EXCEPTION 'Two accessible favorites must persist independently';
  END IF;

  BEGIN
    INSERT INTO public.unit_picker_favorites VALUES (owner_id, hidden_unit);
    RAISE EXCEPTION 'An inaccessible unit was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claim.sub', other_id::text, true);
  IF EXISTS (SELECT 1 FROM public.unit_picker_favorites WHERE user_id = owner_id) THEN
    RAISE EXCEPTION 'Another account can read favorites';
  END IF;
  DELETE FROM public.unit_picker_favorites WHERE user_id = owner_id;
  IF FOUND THEN RAISE EXCEPTION 'Another account can delete favorites'; END IF;
  BEGIN
    INSERT INTO public.unit_picker_favorites VALUES (owner_id, first_unit);
    RAISE EXCEPTION 'Another account can write favorites';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO public.unit_picker_favorites VALUES (other_id, first_unit);

  PERFORM set_config('request.jwt.claim.sub', owner_id::text, true);
  DELETE FROM public.unit_picker_favorites WHERE user_id = owner_id AND unit_id = first_unit;
  IF (SELECT array_agg(unit_id) FROM public.unit_picker_favorites) IS DISTINCT FROM ARRAY[second_unit] THEN
    RAISE EXCEPTION 'Removing one favorite must preserve the other';
  END IF;

  RESET ROLE;
  DELETE FROM public.unit_users WHERE unit = first_unit;
  DELETE FROM public.units WHERE id = first_unit;
  IF EXISTS (SELECT 1 FROM public.unit_picker_favorites WHERE unit_id = first_unit) THEN
    RAISE EXCEPTION 'Deleting a unit left a favorite';
  END IF;
  DELETE FROM public.occasion_users WHERE "user" = owner_id;
  DELETE FROM public.user_info WHERE id = owner_id;
  IF EXISTS (SELECT 1 FROM public.unit_picker_favorites WHERE user_id = owner_id) THEN
    RAISE EXCEPTION 'Deleting a profile left a favorite';
  END IF;
END;
$$;

ROLLBACK;
