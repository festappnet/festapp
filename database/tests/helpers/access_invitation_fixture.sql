-- A trusted renderer fixture, isolated to the test transaction. No provider calls.
CREATE OR REPLACE FUNCTION pg_temp.enqueue_setup_access(p_draft uuid,p_email text,p_hash text,p_sealed jsonb,p_content_hash text,p_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE request jsonb; preview jsonb; preparation uuid; result jsonb; d public.occasion_setup_drafts; cmd uuid;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.data->>'finalizedOccasion' IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='finalize first'; END IF;
 cmd:=md5('setup:'||p_draft||':'||lower(btrim(p_email))||':'||p_role)::uuid;
 request:=jsonb_build_object('scope',jsonb_build_object('type','occasion','id',(d.data->>'finalizedOccasion')::bigint),
  'operation','send_invitation','communication','invite_to_accept','sourceDraft',p_draft,'email',lower(btrim(p_email)),
  'roles',jsonb_build_object('is_editor',p_role='editor','is_editor_view',true));
 preview:=public.preview_member_access(cmd,request);
 IF preview ? 'replay' THEN result:=preview->'replay';
 ELSE
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  preparation:=public.stage_member_access_email(auth.uid(),cmd,preview->>'intentHash',preview->>'previewHash',
   jsonb_build_object('p_sealed',p_sealed,'p_content_hash',p_content_hash),p_hash);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  result:=public.manage_member_access(cmd,request,preparation);
 END IF;
 RETURN jsonb_build_object('status','queued','message_id',result#>'{data,communication,messageId}','replayed',preview ? 'replay');
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.enqueue_setup_access(uuid,text,text,jsonb,text,text) TO authenticated;
