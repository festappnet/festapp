-- One access-change fanout for organizer role edits and removal. No new commit.
CREATE OR REPLACE FUNCTION public.publish_unit_user_access_change_internal_v1(p_commit_id uuid,p_unit bigint,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occasion bigint; v_revision bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.client_commits WHERE commit_id=p_commit_id AND unit=p_unit) THEN
  RAISE foreign_key_violation USING MESSAGE='organizer access fanout requires its commit'; END IF;
  FOR v_occasion IN SELECT ou.occasion FROM public.occasion_users ou
    JOIN public.occasions o ON o.id=ou.occasion
    WHERE o.unit=p_unit AND ou."user"=p_user ORDER BY ou.occasion LOOP
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('occasion_user','occasion',v_occasion,p_user::text,1)
    ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET
      version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
    INSERT INTO public.client_sync_private_scopes
      (component,occasion,user_id,source_revision)
    VALUES ('private_profile',v_occasion,p_user,1)
    ON CONFLICT (component,occasion,user_id) DO UPDATE SET
      source_revision=public.client_sync_private_scopes.source_revision+1,
      updated_at=now() RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (p_commit_id,'private_profile','occasion',v_occasion,
      p_user,v_revision);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.publish_unit_user_access_change_internal_v1(uuid,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
