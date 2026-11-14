-- Apple Wallet on the shared ticket capability and organization connector.

-- SOURCE: ticket_wallet/apple_schema.sql
-- Independent Apple activation on the existing organization connector.
ALTER TABLE eshop.ticket_wallet_integrations
 ADD COLUMN IF NOT EXISTS apple_publishing_ready boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS apple_pass_type_identifier text,
 ADD COLUMN IF NOT EXISTS apple_team_identifier text;
ALTER TABLE eshop.ticket_wallet_integrations ALTER COLUMN issuer DROP NOT NULL;
ALTER TABLE eshop.ticket_wallet_integrations ADD CONSTRAINT ticket_wallet_google_identity CHECK(NOT publishing_ready OR issuer IS NOT NULL);
ALTER TABLE eshop.ticket_wallet_integrations ADD CONSTRAINT ticket_wallet_apple_identity CHECK(
 NOT apple_publishing_ready OR (apple_pass_type_identifier IS NOT NULL AND apple_pass_type_identifier ~ '^pass\.[A-Za-z0-9.-]+$'
 AND apple_team_identifier IS NOT NULL AND apple_team_identifier ~ '^[A-Z0-9]{10}$'));

-- SOURCE: ticket_wallet/settings.sql
CREATE OR REPLACE FUNCTION public.ticket_wallet_enabled(p_feature jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF NOT coalesce(p_feature ? 'wallet_enabled',false) THEN RETURN true; END IF;
 IF jsonb_typeof(p_feature->'wallet_enabled') IS DISTINCT FROM 'boolean' THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid ticket wallet preference'; END IF;
 RETURN (p_feature->>'wallet_enabled')::boolean;
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_enabled(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_enabled(jsonb) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_ready(p_organization bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.is_service_role() AND NOT EXISTS(SELECT 1 FROM public.units u WHERE u.organization=p_organization AND public.can_create_occasion(u.id)) THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=p_organization AND (publishing_ready OR apple_publishing_ready));
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_ready(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_ready(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_fingerprint(p_occasion bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT coalesce((f->>'is_enabled')::boolean,false)::text||'/'||public.ticket_wallet_enabled(f)::text||'/'||public.ticket_wallet_ready(o.organization)::text||'/'||coalesce((SELECT publishing_ready::text||'/'||apple_publishing_ready::text FROM eshop.ticket_wallet_integrations WHERE organization=o.organization),'false/false')
 FROM public.occasions o LEFT JOIN LATERAL (SELECT x f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket') x ON true WHERE o.id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_fingerprint(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_fingerprint(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.validate_ticket_wallet_appearance(p_feature jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE appearance jsonb:=p_feature->'wallet_appearance'; k text; value text;
BEGIN
 IF appearance IS NULL THEN RETURN; END IF;
 IF jsonb_typeof(appearance) IS DISTINCT FROM 'object' OR octet_length(appearance::text)>8192
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(appearance) key WHERE key NOT IN ('background_color','logo','hero_image')) THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid Google Wallet appearance'; END IF;
 FOR k,value IN SELECT key,appearance->>key FROM jsonb_object_keys(appearance) key LOOP
  IF value IS NULL THEN CONTINUE; END IF;
  IF jsonb_typeof(appearance->k) IS DISTINCT FROM 'string' OR
   (k='background_color' AND value !~ '^#?[a-fA-F0-9]{6}$') OR
   (k IN ('logo','hero_image') AND (length(value)>2048 OR value !~ '^https://(img\.festapp\.net/(images|assets)/|a\.img\.festapp\.net/images/)[^?#[:space:]]+$')) THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid Google Wallet appearance'; END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_ticket_wallet_appearance(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_ticket_wallet_appearance(jsonb) TO authenticated,service_role;

-- SOURCE: ticket_wallet/capabilities.sql
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet(p_message uuid,p_ticket bigint,p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) THEN RETURN NULL; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m)
 OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket AND "order"=m.order_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Wallet unavailable'; END IF;
 SELECT * INTO o FROM public.occasions WHERE id=m.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND (publishing_ready OR apple_publishing_ready);
 IF NOT coalesce((f->>'is_enabled')::boolean,false) OR NOT public.ticket_wallet_enabled(f) OR i.organization IS NULL
 OR nullif(btrim(o.title),'') IS NULL OR (o.data->>'timezone' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=o.data->>'timezone'))
 OR o.end_time IS NULL OR o.start_time IS NULL OR o.end_time+interval '7 days'<=now() THEN RETURN NULL; END IF;
 -- Serialize issuance/reissue on the existing ticket; revoked rows never disappear.
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket AND occasion=m.occasion AND state IN ('paid','sent','used') AND ticket_symbol IS NOT NULL AND public.provider_ticket_admission_allowed_internal(id) FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(p_ticket);
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  UPDATE eshop.ticket_wallet_capabilities SET token_hash=p_hash,sealed=p_sealed,recipient=m.recipient,message_id=m.message_id,
   revoked_at=NULL,reissue_after=NULL,event_end_at=o.end_time,expires_at=o.end_time+interval '7 days' WHERE ticket_id=p_ticket RETURNING * INTO c;
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
 END IF;
 IF c.ticket_id IS NULL AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  INSERT INTO eshop.ticket_wallet_capabilities(ticket_id,organization,occasion,order_id,token_hash,sealed,recipient,message_id,expires_at,event_end_at)
  VALUES(p_ticket,m.organization,m.occasion,m.order_id,p_hash,p_sealed,m.recipient,m.message_id,o.end_time+interval '7 days',o.end_time) RETURNING * INTO c;
 END IF;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NULL THEN c.ticket_id:=NULL; END IF;
 IF c.ticket_id IS NOT NULL AND (c.revoked_at IS NOT NULL OR c.expires_at<=now() OR c.recipient IS DISTINCT FROM m.recipient
 OR c.organization<>m.organization OR c.occasion<>m.occasion OR c.order_id<>m.order_id) THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('organization',m.organization,'occasion',m.occasion,'ticketId',p_ticket,'issuer',i.issuer,
 'environment',i.environment,'webOrigin',i.web_origin,'badgeUrls',i.badge_urls,
 'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
 'source',CASE WHEN c.ticket_id IS NOT NULL THEN jsonb_build_object('sealed',c.sealed,'tokenHash',c.token_hash,'generation',c.generation) END);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_ticket_wallet(p_hash text,p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations; n integer; k text;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_source !~ '^[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 DELETE FROM eshop.ticket_wallet_limits WHERE window_at<now()-interval '10 minutes';
 FOREACH k IN ARRAY ARRAY['token:'||p_hash,'source:'||p_source] LOOP
  INSERT INTO eshop.ticket_wallet_limits(key,window_at,attempts) VALUES(k,now(),1)
  ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN 1 ELSE ticket_wallet_limits.attempts+1 END,
  window_at=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN now() ELSE ticket_wallet_limits.window_at END RETURNING attempts INTO n;
  IF n>20 THEN RETURN NULL; END IF;
 END LOOP;
 PERFORM public.refresh_ticket_wallet_term_internal((SELECT ticket_id FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash));
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now();
 IF c.ticket_id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
 IF i.organization IS NULL THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('ticketId',c.ticket_id,'organization',c.organization,'occasion',c.occasion,'issuer',i.issuer,'environment',i.environment,
 'webOrigin',i.web_origin,'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
 'applePassTypeIdentifier',i.apple_pass_type_identifier,'appleTeamIdentifier',i.apple_team_identifier,'projection',public.ticket_wallet_projection_internal(c.ticket_id));
END $$;

-- Explicit support operation. A new generation always requires a fresh valid email intent.
CREATE OR REPLACE FUNCTION public.manage_ticket_wallet(p_ticket bigint,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; scope bigint;
BEGIN
 SELECT occasion INTO scope FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF auth.uid() IS NULL OR public.can_write_orders(scope) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF p_action NOT IN ('revoke','reissue') THEN RAISE invalid_parameter_value; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket FOR UPDATE;
 UPDATE eshop.ticket_wallet_capabilities SET revoked_at=coalesce(revoked_at,now()) WHERE ticket_id=p_ticket;
 -- Reissue retains the tombstone and audit while removing access to the previous source.
 IF p_action='reissue' THEN
  UPDATE eshop.ticket_wallet_capabilities SET generation=generation+1,reissue_after=clock_timestamp(),sealed='{}',token_hash=encode(extensions.gen_random_bytes(32),'hex'),
   recipient='',message_id='00000000-0000-0000-0000-000000000000',expires_at=now() WHERE ticket_id=p_ticket;
 END IF;
 INSERT INTO eshop.ticket_wallet_audit(ticket_id,generation,token_hash,actor,action) VALUES(p_ticket,c.generation,c.token_hash,auth.uid(),p_action);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) TO service_role;
REVOKE ALL ON FUNCTION public.manage_ticket_wallet(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_ticket_wallet(bigint,text) TO authenticated;

-- SOURCE: eshop/get_order_details_for_email.sql
CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    result_data jsonb;
    v_changes jsonb;
    form_fields_data jsonb;
    form_data jsonb;
    form_key uuid;
    latest_history_id bigint;
    v_reply_to_email TEXT;
BEGIN
    -- Retrieve the order, occasion, payment info, and bank account as separate objects
    SELECT jsonb_build_object(
        'order', to_jsonb(o.*) || jsonb_build_object('data', o.data || jsonb_build_object(
          'tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))),
        'occasion', to_jsonb(occ.*)||jsonb_build_object('locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=occ.organization),'cs')),
        -- Same statement snapshot as the ticket feature used by delivery.
        'wallet', jsonb_build_object(
          'feature',(SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'),
          'fingerprint',public.ticket_wallet_fingerprint(occ.id)),
        'payment_info', to_jsonb(pi.*)||jsonb_build_object('collectionAction',public.payment_collection_action_internal(o.id),'providerPayment',CASE WHEN public.payment_method_is_online_internal(pi.payment_method) THEN public.provider_order_payment_projection_internal(o.id) END),
        'bank_account', CASE
            WHEN upper(o.currency_code) = 'EUR'
              AND ba.id IS NOT NULL
              AND nullif(trim(ba.creditor_name), '') IS NULL
            THEN jsonb_set(
              to_jsonb(ba.*),
              '{creditor_name}',
              to_jsonb(left(trim(regexp_replace(org.title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70))
            )
            ELSE to_jsonb(ba.*)
        END
    )
    INTO result_data
    FROM eshop.orders AS o
    LEFT JOIN public.occasions AS occ ON o.occasion = occ.id
    LEFT JOIN public.organizations AS org ON occ.organization = org.id
    LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
    LEFT JOIN eshop.bank_accounts AS ba ON pi.bank_account = ba.id
    WHERE o.id = p_order_id;

    -- Check if the order was found
    IF result_data IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found.');
    END IF;

    -- Call the function you provided to get the email
    SELECT get_reply_to_email_for_order(p_order_id) INTO v_reply_to_email;

    -- Add the email to the result data. jsonb_build_object handles NULLs gracefully.
    result_data := result_data || jsonb_build_object('reply_to', v_reply_to_email);


    v_changes := public.get_order_change_summary_v1(p_order_id);
    latest_history_id := (v_changes->>'latestHistoryId')::bigint;
    result_data := result_data || jsonb_build_object(
      'latest_history_id', latest_history_id,
      'reference_history', v_changes#>'{referenceOrder,data}',
      'order_changes', v_changes);

    -- Extract the form's unique key from the order's data
    form_key := (result_data->'order'->'data'->>'form')::uuid;

    -- If a form key exists, fetch all associated form fields
    IF form_key IS NOT NULL THEN
        -- 2. Modified query to fetch both form_fields and form_data at the same time
        SELECT
            jsonb_object_agg(ff.id, to_jsonb(ff.*)), -- All fields
            public.effective_form_metadata_internal(f.data, u.data) -- Communication metadata without analytics policy
        INTO
            form_fields_data,
            form_data
        FROM
            public.form_fields AS ff
        JOIN
            public.forms AS f ON ff.form = f.id
        JOIN public.occasions form_occasion ON form_occasion.id = f.occasion
        JOIN public.units u ON u.id = form_occasion.unit
        WHERE
            f.key = form_key
        GROUP BY
            f.id, u.data; -- Group by the form used for effective data

        -- If form fields were found, add them to the result data
        IF form_fields_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_fields', form_fields_data);
        END IF;

        -- 3. Added this block to merge the form_data
        IF form_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_data', form_data);
        END IF;
    END IF;

    -- Return a success response with the collected data
    RETURN jsonb_build_object('code', 200, 'data', result_data);

END;
$$;
-- The worker is the external consumer. Already-authorized definer commands
-- (contact repair) share this read owner without granting it to clients.
REVOKE ALL ON FUNCTION public.get_order_details_for_email(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_details_for_email(bigint) TO service_role;

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','795b29c048acb37bc949683bfc586f43',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','337628341725ae78a7c14a130a0fe7a4',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','d8c6d2e6a64880af2fa1e5553dbf85f5',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','4a2bacea00089021e673b0ef3fd67237',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.ticket_wallet_enabled(jsonb)','ccbb73fd52b030315763e2be50b8e7a7',false,true),
  ('public.ticket_wallet_fingerprint(bigint)','3f120ad5ccdd4541ae4d425d548ffb72',true,true),
  ('public.ticket_wallet_ready(bigint)','25dc8cba98b32f00f8f0980b207fa197',true,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','19ef5dae0f946b65406440e82703e2cd',true,true),
  ('public.validate_ticket_layout(jsonb)','53d7703a06dbde87349a0ac04e50cd54',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true),
  ('public.validate_ticket_wallet_appearance(jsonb)','bdcc55cb2a986056fbae005acee1990c',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;
