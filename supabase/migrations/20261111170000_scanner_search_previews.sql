-- Rich ticket-search previews and authoritative selection within one scanner session.

-- Source: database/functions/scanning/projection.sql
-- Set based, minimal projection shared by lookup, search and immutable snapshots.
CREATE OR REPLACE FUNCTION public.scanner_ticket_projection_internal(p_occasion bigint,p_config jsonb,p_ticket bigint DEFAULT NULL)
RETURNS TABLE(ticket_id bigint,dto jsonb) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH base AS MATERIALIZED (
 SELECT t.*,o.id oid,o.form,o.state order_state,o.updated_at order_updated,o.data order_data,o.note_hidden order_note_hidden,
 pi.amount,pi.paid,public.provider_ticket_requires_online_internal(t.id) online_required,
 coalesce(td.value,'{}'::jsonb) ticket_data,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders oz ON oz.id=z."order"
 WHERE z.ticket=t.id AND (oz.occasion IS DISTINCT FROM t.occasion OR oz.state IN ('stock','storno','waitlisted','preparing_payment'))) bad_order
 FROM eshop.tickets t
 JOIN LATERAL (SELECT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=t.id ORDER BY x."order" LIMIT 1) x ON true
 JOIN eshop.orders o ON o.id=x."order"
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN LATERAL (SELECT value FROM jsonb_array_elements(coalesce(o.data->'tickets','[]'::jsonb)) WHERE value->>'id'=t.id::text LIMIT 1) td ON true
 WHERE t.occasion=p_occasion AND (p_ticket IS NULL OR t.id=p_ticket)
 ), projected AS (
 SELECT b.*,coalesce(nullif(trim(concat_ws(' ',nullif(trim(b.order_data->>'name'),''),nullif(trim(b.order_data->>'surname'),''))),''),
 (SELECT string_agg(nullif(trim(a.value#>>'{}'),''),' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.order_data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND NOT ff.is_ticket_field WHERE ff.type IN ('name','surname'))) purchaser_name,
 coalesce((SELECT string_agg(a.value#>>'{}',' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND ff.is_ticket_field WHERE ff.type IN ('name','surname')),
 (SELECT string_agg(v.value#>>'{}',' ' ORDER BY v.key) FROM jsonb_each(b.ticket_data) v WHERE v.key IN ('name','surname')),
 (SELECT concat_ws(' ',u.name,u.surname) FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" WHERE ou.ticket=b.id AND ou.occasion=p_occasion LIMIT 1),b.ticket_symbol) holder_name,
 (b.state IN ('sent','paid','ordered') AND b.ticket_symbol IS NOT NULL AND NOT b.bad_order AND b.order_state NOT IN ('stock','storno','waitlisted','preparing_payment') AND public.provider_ticket_admission_allowed_internal(b.id)) eligible
 FROM base b)
 SELECT b.id,jsonb_strip_nulls(jsonb_build_object('ticket_id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated_at',b.updated_at,
 'batch_title',(SELECT tb.title FROM eshop.ticket_batch_items bi JOIN eshop.ticket_batches tb ON tb.id=bi.batch_id WHERE bi.ticket_id=b.id AND tb.occasion=p_occasion),
 'order_id',b.oid,'order_state',b.order_state,'purchaser_name',b.purchaser_name,'holder_name',b.holder_name,'admission_allowed',coalesce(b.eligible AND (b.state<>'ordered' OR (p_config#>>'{admission,allow_unpaid_online}')::boolean),false),
 'requires_unpaid_confirmation',b.state='ordered' AND NOT b.bad_order AND b.order_state<>'stock','unavailable_reason',CASE WHEN b.order_state='stock' THEN 'not_sold' END,'online_required',b.online_required,
 'eligibility_fingerprint',encode(digest(jsonb_build_object('v',1,'id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated',b.updated_at,
 'parents',(SELECT jsonb_agg(CASE WHEN pi.payment_method<>'bank' THEN jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid,pi.returned,pi.payment_method,o.email_payment_version) ELSE jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid) END ORDER BY o.id) FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE z.ticket=b.id))::text,'sha256'),'hex'),
 'remaining_amount',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN greatest(0,coalesce(b.amount,0)-coalesce(b.paid,0)) END,
 'order_note',nullif(trim(b.order_data->>'note'),''),'note',nullif(trim(b.note),''),
 'order_note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.order_note_hidden END,
 'note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.note_hidden END,
 'products',coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'title',p.title,'short_title',nullif(trim(p.data->>'short_title'),''),'type_id',p.product_type,'type',pt.type,'type_title',pt.title,
 'price',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN p.price END)) ORDER BY array_position(ARRAY(SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,order}')),p.id) NULLS LAST,p."order",p.id)
 FROM eshop.products p LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=b.id AND z.product=p.id)
 AND ((p_config#>>'{products,mode}')='all' OR ((p_config#>>'{products,mode}')='selected' AND (p_config#>'{products,ids}') @> to_jsonb(ARRAY[p.id])))),'[]'::jsonb),
 'spot',(SELECT s.title FROM eshop.spots s JOIN eshop.order_product_ticket z ON z.id=s.order_product_ticket WHERE z.ticket=b.id ORDER BY s.id LIMIT 1),
 'spot_group',(SELECT jsonb_build_object('blueprint_id',bp.id,'id',g->>'id','title',g->>'label')
 FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket
 JOIN eshop.blueprints bp ON bp.id=sp.blueprint
 JOIN eshop.blueprint_seat_bindings sb ON sb.blueprint=bp.id AND sb.spot=sp.id
 CROSS JOIN LATERAL jsonb_array_elements(bp.layout->'nodes') g
 WHERE z.ticket=b.id AND sp.occasion=p_occasion AND g->>'id'=sb.group_node::text
 AND g->>'kind' IN ('group','table')
 AND bp.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) ORDER BY sp.id LIMIT 1),
 'fields',coalesce((SELECT jsonb_agg(jsonb_build_object('key',f->>'key','label',f->>'label','value',
 CASE f->>'source' WHEN 'builtin' THEN CASE f->>'key' WHEN 'holder_name' THEN to_jsonb(b.holder_name) WHEN 'note' THEN to_jsonb(b.note)
 WHEN 'spot' THEN (SELECT to_jsonb(sp.title) FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket WHERE z.ticket=b.id ORDER BY sp.id LIMIT 1)
 WHEN 'groups' THEN (SELECT jsonb_agg(gi.title ORDER BY gi.id) FROM public.occasion_users ou JOIN public.user_groups ug ON ug."user"=ou."user" JOIN public.user_group_info gi ON gi.id=ug."group" WHERE ou.ticket=b.id AND ou.occasion=p_occasion AND gi.occasion=p_occasion) END
 ELSE (SELECT e->(f->>'field_id') FROM jsonb_array_elements(CASE WHEN f->>'source'='order_field' THEN coalesce(b.order_data->'fields','[]'::jsonb) ELSE coalesce(b.data->'fields','[]'::jsonb) END) e WHERE e ? (f->>'field_id') LIMIT 1) END,
 'missing',CASE WHEN f->>'source'='builtin' THEN false ELSE NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.id=(f->>'field_id')::bigint AND ff.form=b.form) END,
 'hide_empty',coalesce((f->>'hide_empty')::boolean,true),'default_visible',coalesce((f->>'default_visible')::boolean,true)) ORDER BY idx)
 FROM jsonb_array_elements(p_config->'fields') WITH ORDINALITY a(f,idx) WHERE f->>'source'='builtin' OR (f->>'form_id')::bigint=b.form),'[]'::jsonb)))
 FROM projected b;
$$;

-- Source: database/functions/scanning/admission.sql
CREATE OR REPLACE FUNCTION public.scanner_lookup_ticket_internal(p_session uuid,p_token text,p_symbol text,p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; tid bigint; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF p_ticket IS NOT NULL AND NOT coalesce((cfg.config#>>'{manual_search,tickets}')::boolean,false) THEN
  RAISE insufficient_privilege USING MESSAGE='manual_search_disabled';
 END IF;
 IF p_ticket IS NOT NULL THEN
  SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.id=p_ticket;
 ELSE
  SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol=p_symbol LIMIT 1;
 END IF;
 IF p_ticket IS NULL AND tid IS NULL AND p_symbol ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN
  SELECT t.id INTO tid FROM public.occasion_users ou JOIN eshop.tickets t ON t.id=ou.ticket WHERE ou.occasion=s.occasion_id AND ou."user"=p_symbol::uuid AND t.occasion=s.occasion_id LIMIT 1;
 END IF;
 SELECT dto INTO result FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid) WHERE ticket_id=tid;
 IF result IS NOT NULL THEN result:=result||jsonb_build_object('can_reset_password',public.scanner_can_reset_password_internal(s.occasion_id,tid)); END IF;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'reason',CASE WHEN result IS NULL THEN 'not_found' ELSE 'found' END,
 'data',result,'settings_revision',cfg.revision,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.scanner_lookup_ticket_internal(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket(p_session uuid,p_token text,p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN public.scanner_lookup_ticket_internal(p_session,p_token,p_symbol,NULL);
END $$;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket_by_id(p_session uuid,p_token text,p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN public.scanner_lookup_ticket_internal(p_session,p_token,NULL,p_ticket);
END $$;
REVOKE ALL ON FUNCTION public.lookup_scanner_ticket_by_id(uuid,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_scanner_ticket_by_id(uuid,text,bigint) TO anon,authenticated,service_role;

NOTIFY pgrst, 'reload schema';
