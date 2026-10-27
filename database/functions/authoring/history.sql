CREATE OR REPLACE FUNCTION public.get_authoring_history(p_occasion bigint,p_organization bigint,p_unit bigint,p_action text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; lim int:=coalesce((p_payload->>'limit')::int,50); commit_row public.client_commits%ROWTYPE;
 order_id bigint:=(p_payload->>'orderId')::bigint; include_unit boolean:=coalesce((p_payload->>'includeUnit')::boolean,false);
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF lim NOT BETWEEN 1 AND 100 OR (include_unit AND (p_unit IS NULL OR NOT public.can_read_unit_client_commits(p_unit))) THEN
  RAISE insufficient_privilege USING MESSAGE='invalid history scope'; END IF;
 IF order_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order outside history scope'; END IF;
 IF p_action='commits' THEN
  RETURN public.get_client_commits_scoped_internal_v1(p_occasion,(p_payload#>>'{before,occurredAt}')::timestamptz,(p_payload#>>'{before,commitId}')::uuid,lim,'{}',include_unit,false);
 ELSIF p_action='commit' THEN
  SELECT * INTO commit_row FROM public.client_commits WHERE commit_id=(p_payload->>'commitId')::uuid;
  IF commit_row.commit_id IS NULL OR NOT coalesce(commit_row.occasion=p_occasion OR (include_unit AND commit_row.unit=p_unit),false) THEN
   RAISE insufficient_privilege USING MESSAGE='commit outside history scope'; END IF;
  IF (SELECT count(*) FROM public.client_commit_items WHERE commit_id=commit_row.commit_id)>500 THEN RAISE invalid_parameter_value USING MESSAGE='audit entry exceeds bounded authoring detail; use ordinary UI'; END IF;
  result:=public.get_client_commit_v1(commit_row.commit_id);
  IF result->>'code'<>'200' THEN RAISE insufficient_privilege USING MESSAGE='commit read denied'; END IF;
  -- Fanout metadata must not disclose identities of unrelated scopes.
  result:=jsonb_set(result,'{data,components}',coalesce((SELECT jsonb_agg(c) FROM jsonb_array_elements(result#>'{data,components}') c
   WHERE (c->>'scopeType'='occasion' AND (c->>'scopeId')::bigint=p_occasion) OR (include_unit AND c->>'scopeType'='unit' AND (c->>'scopeId')::bigint=p_unit)),'[]'::jsonb));
  RETURN result;
 ELSIF p_action='activity' THEN
  RETURN public.get_client_activity_v1(p_occasion,(p_payload->>'from')::timestamptz,(p_payload->>'to')::timestamptz);
 ELSIF p_action='orders' THEN
  IF order_id IS NULL OR NOT public.can_read_orders(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order history read denied'; END IF;
  SELECT jsonb_build_object('code',200,'data',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id DESC),'[]'::jsonb)) INTO result FROM (
   SELECT h.id,h.created_at AS "createdAt",h.state,h.price::text AS price,h.currency_code AS currency,
    nullif(concat_ws(' ',u.name,u.surname),'') AS "actorDisplay"
   FROM eshop.orders_history h LEFT JOIN public.user_info u ON u.id=h.created_by WHERE h."order"=order_id
    AND (p_payload->>'beforeId' IS NULL OR h.id<(p_payload->>'beforeId')::bigint) ORDER BY h.id DESC LIMIT lim) page;
  RETURN result;
 ELSIF p_action='email' THEN
  IF NOT coalesce(public.email_report_allowed(p_organization,p_occasion,NULL),false) THEN RAISE insufficient_privilege USING MESSAGE='delivery history read denied'; END IF;
  result:=public.get_email_delivery_page(p_occasion,(p_payload->>'beforeId')::bigint,lim,order_id,p_payload->>'kind',p_payload->>'state',p_organization,NULL,NULL,false);
  RETURN jsonb_build_object('code',200,'data',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r->'id','kind',r->'message_kind','orderId',r->'order_id','createdAt',r->'created_at',
   'acceptedAt',r->'accepted_at','deliveredAt',r->'delivered_at','bouncedAt',r->'bounced_at','complainedAt',r->'complained_at','state',r->'state','postActionState',r->'post_action_state') ORDER BY (r->>'id')::bigint DESC)
   FROM jsonb_array_elements(result) r),'[]'::jsonb));
 ELSIF p_action='feedback' THEN
  RETURN public.get_event_feedback_export_page_internal_v1(p_occasion,(p_payload->>'after')::bigint,lim);
 END IF;
 RAISE invalid_parameter_value USING MESSAGE='unknown history projection';
END $$;
REVOKE ALL ON FUNCTION public.get_authoring_history(bigint,bigint,bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_authoring_history(bigint,bigint,bigint,text,jsonb) TO authenticated,service_role;
