DO $$
DECLARE org bigint; unit_id bigint; connection uuid; claim jsonb; newer jsonb; receipt jsonb; checked timestamptz;
 status jsonb:=jsonb_build_object('accountId','acct_statusFixture','businessName','Organizer status','country','CZ',
  'modelVerified',true,'chargesEnabled',true,'payoutsEnabled',false,'cardPaymentsActive',true);
 event jsonb:=jsonb_build_object('id','evt_statusFixture','bodyHash',repeat('b',64),'accountId','acct_statusFixture','livemode',false,'type','account.updated','created',extract(epoch FROM clock_timestamp())::bigint);
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title) VALUES('Stripe status tenant') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Status organizer',org) RETURNING id INTO unit_id;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused)
  VALUES(org,unit_id,'acct_statusFixture',false,'connected',false) RETURNING id INTO connection;
 PERFORM assert_eq(public.claim_stripe_connection_status_internal('acct_unrelated',false)->>'disposition','unrelated','unknown account never causes a provider lookup');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM assert_eq(public.claim_stripe_connection_status_internal('acct_statusFixture',false)->>'disposition','busy','parallel lifecycle reads serialize');
 receipt:=public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,status,event);
 PERFORM assert_true((receipt->>'committed')::boolean,'current readiness commits with inbox receipt');
 PERFORM assert_true((SELECT charges_enabled AND NOT payouts_enabled AND NOT paused FROM eshop.stripe_connections WHERE id=connection),'payout restrictions alone do not stop receiving');
 SELECT checked_at INTO checked FROM eshop.stripe_connections WHERE id=connection;
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM public.fail_stripe_connection_status_internal(connection,extensions.gen_random_uuid());
 PERFORM assert_true((SELECT status_lease=(claim->>'lease')::uuid FROM eshop.stripe_connections WHERE id=connection),'stale worker cannot clear another status lease');
 PERFORM public.fail_stripe_connection_status_internal(connection,(claim->>'lease')::uuid);
 PERFORM assert_true((SELECT status_failures=1 AND checked_at=checked AND next_check_at>clock_timestamp() FROM eshop.stripe_connections WHERE id=connection),'failed provider reads retain last verification time and back off');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,status,event);
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_event_inbox WHERE connection_id=connection),1::bigint,'repeated lifecycle event commits once');
 PERFORM assert_true((SELECT status_lease IS NULL FROM eshop.stripe_connections WHERE id=connection),'duplicate receipt releases only its fresh claimed lease');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,status||jsonb_build_object('chargesEnabled',false),NULL);
 PERFORM assert_eq((SELECT state FROM eshop.stripe_connections WHERE id=connection),'restricted','lost charge capability stops future attempts');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,status||jsonb_build_object('modelVerified',false),NULL);
 PERFORM assert_true((SELECT paused AND NOT model_verified FROM eshop.stripe_connections WHERE id=connection),'an unverified financial model cannot receive payments');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,status,NULL);
 PERFORM assert_true((SELECT paused FROM eshop.stripe_connections WHERE id=connection),'provider refresh never undoes a manual/safety pause');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,jsonb_build_object('accountId','acct_statusFixture','accessUnavailable',true),
  event||jsonb_build_object('id','evt_statusRevoked','type','account.application.deauthorized'));
 PERFORM assert_true((SELECT state='revoked' AND paused AND NOT charges_enabled AND business_name='Organizer status' FROM eshop.stripe_connections WHERE id=connection),'lost platform access stops new sales and preserves organizer identity');
 claim:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 UPDATE eshop.stripe_connections SET status_lease_expires_at=clock_timestamp()-interval '1 second' WHERE id=connection;
 newer:=public.claim_stripe_connection_status_internal('acct_statusFixture',false);
 BEGIN
  PERFORM public.commit_stripe_connection_status_internal(connection,(claim->>'lease')::uuid,status,NULL);RAISE EXCEPTION 'stale readiness accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_CONNECTION_STATUS_INVALID' THEN RAISE; END IF; END;
 PERFORM public.commit_stripe_connection_status_internal(connection,(newer->>'lease')::uuid,status,NULL);
 PERFORM assert_eq((SELECT state FROM eshop.stripe_connections WHERE id=connection),'revoked','a provider refresh is not a new OAuth authorization');
 PERFORM assert_false(has_function_privilege('authenticated','public.commit_stripe_connection_status_internal(uuid,uuid,jsonb,jsonb)','EXECUTE'),'client cannot invent readiness or revoke another account');
END $$;
