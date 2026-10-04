-- Internal initializer shared by password and externally verified registration.
CREATE OR REPLACE FUNCTION public.initialize_registration_unit_v1(p_user uuid,p_organization bigint,p_raw_email text,p_title text)
RETURNS bigint LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  INSERT INTO public.units(title,organization,data) VALUES(p_title,p_organization,jsonb_build_object('reply_to',lower(btrim(p_raw_email)),'timezone','Europe/Prague')) RETURNING id INTO v_unit;
  INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES(v_unit,p_user,true,true,true);
  RETURN v_unit;
END $$;
REVOKE ALL ON FUNCTION public.initialize_registration_unit_v1(uuid,bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_registration_unit_v1(uuid,bigint,text,text) TO service_role;
