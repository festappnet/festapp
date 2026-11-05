DO $$
DECLARE org bigint; uid bigint; occ bigint; fid bigint; cid uuid; sid uuid; payload jsonb; m public.email_messages; msg jsonb; permit jsonb; expiry timestamptz;
 hash text:=repeat('c',64); uh text:=repeat('d',64); slug text; baseline_count bigint;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title) VALUES('Životní cyklus upozornění') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO uid;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Ples',gen_random_uuid()::text,org,uid,now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,is_open,data) VALUES(occ,true,jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'),'sale_opening_notifications','{"enabled":true}'::jsonb)) RETURNING id INTO fid;
 slug:=public.reserve_public_link_internal('form',fid,NULL,true);UPDATE public.forms SET link=slug WHERE id=fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 SELECT id INTO cid FROM public.sale_opening_campaigns WHERE form_id=fid;
 payload:=jsonb_build_object('formLink',slug,'email','lifecycle@example.invalid','lang','cs',
 'unsubscribe',jsonb_build_object('hash',uh,'envelope',jsonb_build_object('v','1','ciphertext',repeat('y',48))));
 -- Ordinary queue admission rejects and rolls back the entire subscription.
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.ordinary.recipient.burst';
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.ordinary',uid,org),jsonb_build_object('unit',uid,'organization',org,'recipient',public.abuse_recipient_key_v1('lifecycle@example.invalid')),jsonb_build_object('growth',0));
 BEGIN PERFORM public.sale_opening_notification_command('subscribe',payload);RAISE EXCEPTION 'quota accepted';EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL;END;
 PERFORM assert_eq((SELECT count(*) FROM public.sale_opening_subscriptions WHERE campaign_id=cid),0::bigint,'Failed admission leaves no contact or capability');
 UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE rule_key='email.ordinary.recipient.burst';
 PERFORM public.sale_opening_notification_command('subscribe',payload);
 SELECT id INTO sid FROM public.sale_opening_subscriptions WHERE campaign_id=cid;
 -- Changing the recipient cannot bypass the shared tenant budget.
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.ordinary.unit.day';
 BEGIN
  PERFORM public.sale_opening_notification_command('subscribe',jsonb_set(jsonb_set(payload,'{email}','"different@example.invalid"'),'{unsubscribe,hash}',to_jsonb(repeat('e',64))));
  RAISE EXCEPTION 'Rotating recipient bypassed tenant quota';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM public.sale_opening_subscriptions WHERE campaign_id=cid),1::bigint,'Tenant limit rejects rotating addresses without storing contacts');
 UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE rule_key='email.ordinary.unit.day';

 UPDATE public.forms SET data=jsonb_set(data,'{schedule,start_time}',to_jsonb(now()-interval '1 minute')) WHERE id=fid;
 -- Pausing collection preserves active delivery commitments.
 UPDATE public.forms SET data=jsonb_set(data,'{sale_opening_notifications,collection_paused}','true') WHERE id=fid;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.backlog.unit.bytes';
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.email_messages WHERE data->>'subscription_id'=sid::text AND message_kind='sale_opening_opened'),'Fanout quota denial leaves the contact retryable');
 UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE rule_key='email.backlog.unit.bytes';
 PERFORM public.maintain_sale_opening_notifications(100);
 SELECT * INTO m FROM public.email_messages WHERE data->>'subscription_id'=sid::text AND message_kind='sale_opening_opened';
 PERFORM assert_not_null(m.message_id,'Recovery emits the original launch intent');
 SELECT opened_at INTO expiry FROM public.sale_opening_campaigns WHERE id=cid;
 -- The real worker claim/prepare path must still recheck no-order launches.
 UPDATE public.email_messages SET workflow_state='cancelled' WHERE organization<>org OR message_kind<>'sale_opening_opened';
 UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=10,daily_quota=1000,provider_sent_24h=0,worker_url=NULL,next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL;
 msg:=public.claim_email();
 PERFORM assert_eq(msg->>'message_id',m.message_id::text,'Worker claims the launch');
 PERFORM public.prepare_email((msg->>'message_id')::uuid,(msg->>'lease_token')::uuid,'{"sealed":"snapshot"}');
 UPDATE public.forms SET is_open=false WHERE id=fid;
 permit:=public.begin_email_send((msg->>'attempt_id')::uuid,(msg->>'lease_token')::uuid);
 PERFORM assert_eq(permit->>'disposition','cancelled','Final fenced send refuses a cached snapshot after closure');
 UPDATE public.forms SET is_open=true WHERE id=fid;
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE id=m.id),'pending','Temporary closure recovers the same unstarted intent');
 PERFORM assert_eq((SELECT opened_at FROM public.sale_opening_campaigns WHERE id=cid),expiry,'Reopening never resets the 24 hour window');
 -- Unknown provider results cannot be resurrected by maintenance.
 UPDATE public.email_messages SET workflow_state='unknown' WHERE id=m.id;
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq((SELECT workflow_state FROM public.email_messages WHERE id=m.id),'unknown','Unknown remains fenced');
 UPDATE public.forms SET data=jsonb_set(data,'{sale_opening_notifications,enabled}','false') WHERE id=fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE id=cid),'cancelled','Ending after fanout completion cancels unsent commitments');
 PERFORM assert_false(public.email_intent_valid(m),'Ending invalidates no-order messages regardless of cached snapshot');
 -- Retention removes source contacts and tokens and retains anonymous totals.
 UPDATE public.sale_opening_subscriptions SET closed_at=now()-interval '31 days' WHERE id=sid;
 PERFORM public.maintain_sale_opening_notifications(100);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.sale_opening_subscriptions WHERE id=sid),'Closed contact removed within retention sweep');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.sale_opening_capabilities WHERE subscription_id=sid),'Encrypted capability sources are removed with contact');
 PERFORM assert_eq((SELECT retained_counts->>'closed' FROM public.sale_opening_campaigns WHERE id=cid),'1','Anonymous total survives');
END $$;
