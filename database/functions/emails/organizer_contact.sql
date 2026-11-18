INSERT INTO public.abuse_policy_rules
 (rule_key, budget_key, scope_kind, kind, window_seconds, bucket_seconds, base_limit, hard_cap)
VALUES
 ('organizer.contact.global', 'organizer.contact', 'global', 'rolling', 900, 60, 20, 20),
 ('organizer.contact.sender', 'organizer.contact', 'recipient', 'rolling', 900, 60, 3, 3)
ON CONFLICT (rule_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.enqueue_organizer_contact_v1(
 p_id uuid, p_reply_to text, p_sealed jsonb, p_content_hash text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 v_organization constant bigint := 3;
 v_key text := 'organizer-contact:' || p_id::text;
 v_previous_hash text;
 v_policy jsonb;
 v_result jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_id IS NULL OR p_reply_to IS NULL OR length(p_reply_to) NOT BETWEEN 3 AND 254
  OR p_content_hash IS NULL OR p_content_hash !~ '^[0-9a-f]{64}$'
  OR p_sealed IS NULL OR p_sealed->>'v' IS DISTINCT FROM '1'
 THEN RAISE invalid_parameter_value USING MESSAGE='invalid_organizer_contact'; END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended(v_key, 0));
 SELECT data->>'content_hash' INTO v_previous_hash
 FROM public.email_messages
 WHERE organization=v_organization AND message_kind='custom' AND dedupe_key=v_key;
 IF FOUND THEN
  RETURN CASE WHEN v_previous_hash=p_content_hash THEN 'accepted' ELSE 'conflict' END;
 END IF;

 SELECT jsonb_build_object('revision', v.revision, 'rules', jsonb_agg(to_jsonb(r)))
 INTO v_policy
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 WHERE r.budget_key='organizer.contact'
 GROUP BY v.revision HAVING count(*)=2;
 PERFORM public.abuse_charge_v1(
  v_policy,
  jsonb_build_object('global', 'vstupenky.online',
   'recipient', public.abuse_recipient_key_v1(p_reply_to))
 );
 v_result := public.enqueue_prepared_email(
  'custom', jsonb_build_object('organization', v_organization),
  'info@vstupenky.online', p_sealed, v_key, p_content_hash, 'ORGANIZER_CONTACT'
 );
 UPDATE public.email_messages SET tracking_policy='disabled'
 WHERE message_id=(v_result->>'message_id')::uuid;
 RETURN 'accepted';
END $$;

REVOKE ALL ON FUNCTION public.enqueue_organizer_contact_v1(uuid,text,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_organizer_contact_v1(uuid,text,jsonb,text)
 TO service_role;
