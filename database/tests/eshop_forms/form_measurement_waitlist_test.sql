-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(1); f bigint:=(x->>'form')::bigint; r jsonb; w jsonb; ids bigint[]; payload jsonb;
 command uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); reg_command uuid:=gen_random_uuid(); reg_client uuid:=gen_random_uuid(); reg_payload jsonb;
 source bigint; regular bigint; token text:=repeat('a',64); facts jsonb;
BEGIN
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','local waitlist conversion test');
 UPDATE public.forms SET data=coalesce(data,'{}')||'{"analytics":{"enabled":true}}' WHERE id=f;
 r:=public.create_ticket_order_client_sync_v1(pg_temp.checkout(x),gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r#>>'{data,code}','200','fill capacity');regular:=(r#>>'{data,order,id}')::bigint;
 reg_payload:=jsonb_build_object('form',x->'key','email','regression@example.invalid','tickets',jsonb_build_array(jsonb_build_object('fields','[]'::jsonb)));
 r:=public.execute_waitlist_command_client_sync_v1('register',reg_payload,reg_command,reg_client,NULL,jsonb_build_array(pg_temp.delivery('waitlist_confirmation',repeat('b',64))));
 PERFORM assert_eq(r#>>'{data,analytics,event}','generate_lead','waitlist registration has server lead facts');
 facts:=r#>'{data,analytics}';source:=(r#>>'{data,order,id}')::bigint;
 r:=public.execute_waitlist_command_client_sync_v1('register',reg_payload,reg_command,reg_client,NULL,jsonb_build_array(pg_temp.delivery('waitlist_confirmation',repeat('b',64))));
 PERFORM assert_eq(r#>'{data,analytics}',facts,'registration replay preserves stable lead identity');
 PERFORM public.update_order_and_tickets_to_storno_221(regular);
 w:=pg_temp.offer(x,source,1,token);ids:=pg_temp.ticket_ids(source);
 payload:=jsonb_build_object('offerId',w->'id','ticketIds',to_jsonb(ids),'token',token,'orderDetails',pg_temp.checkout(x,ids));
 r:=public.execute_waitlist_command_client_sync_v1('accept',payload,command,client,NULL);
 PERFORM assert_eq(r#>>'{data,code}','200','anonymous capability acceptance succeeds');
 PERFORM assert_eq(r#>>'{data,analytics,event}','purchase','accepted paid offer projects same canonical purchase');
 PERFORM assert_eq(r#>>'{data,analytics,ecommerce,value}','100.00','canonical accepted price');
 facts:=r#>'{data,analytics}';
 r:=public.execute_waitlist_command_client_sync_v1('accept',payload,command,client,NULL);
 PERFORM assert_eq(r#>'{data,analytics}',facts,'accepted offer response loss recovers same conversion');
 PERFORM assert_eq(pg_temp.ticket_ids(source),ids,'existing waitlist ticket identities preserved');
END $$;
