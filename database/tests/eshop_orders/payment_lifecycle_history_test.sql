-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Characterization: preserve the existing snapshot format and event cardinality.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint;
 original jsonb; edited jsonb; delivered jsonb; snapshot jsonb; result jsonb;
 command uuid:=gen_random_uuid(); cancel_command uuid:=gen_random_uuid(); mid uuid;
 row_json jsonb; projected jsonb;
BEGIN
 original:=pg_temp.payment_history(oid);
 PERFORM assert_eq(jsonb_array_length(original),1,'checkout writes one historical snapshot');
 PERFORM assert_eq(original#>>'{0,state}','ordered'::text,'creation history keeps ordered state');
 PERFORM assert_eq(original#>'{0,data,input_data,form}',to_jsonb((SELECT key FROM forms WHERE id=(x->>'form')::bigint)),
  'creation history preserves its input_data envelope');
 PERFORM assert_eq(original#>>'{0,data,tickets,0,id}',x->>'ticket','creation history retains ticket identity');
 PERFORM assert_eq(original#>>'{0,created_by}',x->>'actor','creation history retains actor');

 PERFORM pg_temp.payment_edit(x,800,command);
 edited:=pg_temp.payment_history(oid);
 PERFORM assert_eq(jsonb_array_length(edited),2,'one real edit appends exactly one snapshot');
 PERFORM assert_eq(edited->0,original->0,'edit leaves the original row byte-for-byte equivalent as JSON');
 PERFORM assert_eq(edited#>>'{1,state}','ordered'::text,'unpaid edit retains ordered history');
 PERFORM assert_eq((edited#>>'{1,price}')::numeric,800::numeric,'history captures edited price');
 PERFORM assert_eq(edited#>'{1,data}',(SELECT data FROM eshop.orders WHERE id=oid),'edit stores the full current order snapshot');
 PERFORM assert_eq(edited#>>'{1,created_by}',x->>'actor','edit retains its actor');
 PERFORM pg_temp.payment_edit(x,800,command);
 PERFORM pg_temp.payment_edit(x,800);
 PERFORM assert_eq(pg_temp.payment_history(oid),edited,'receipt replay and unchanged new command append no history');

 PERFORM pg_temp.payment_pair(x,800);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'real bank pairing pays order');
 PERFORM assert_eq(pg_temp.payment_history(oid),edited,'payment currently appends no order snapshot');
 mid:=pg_temp.payment_accept_tickets(x);
 delivered:=pg_temp.payment_history(oid);
 PERFORM assert_eq(jsonb_array_length(delivered),3,'accepted ticket delivery appends one snapshot');
 PERFORM assert_eq(delivered->0,original->0,'delivery preserves creation history');
 PERFORM assert_eq(delivered->1,edited->1,'delivery preserves product-edit history');
 PERFORM assert_eq(delivered#>>'{2,state}','sent'::text,'delivery history records sent');
 PERFORM assert_eq(delivered#>'{2,data}',(SELECT data FROM eshop.orders WHERE id=oid),'delivery stores current snapshot');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.apply_email_post_actions(mid);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq(pg_temp.payment_history(oid),delivered,'email projection retry appends no duplicate');

 SET LOCAL ROLE authenticated;
 result:=public.storno_order_client_sync_v1(oid,cancel_command);
 RESET ROLE;
 PERFORM assert_eq(result->>'status','applied'::text,'cancellation commits');
 snapshot:=pg_temp.payment_history(oid);
 PERFORM assert_eq(jsonb_array_length(snapshot),4,'cancellation appends exactly one snapshot');
 PERFORM assert_eq(snapshot#>>'{3,state}','storno'::text,'cancellation retains established state name');
 PERFORM assert_eq((snapshot#>>'{3,price}')::numeric,0::numeric,'cancellation history price is zero');
 PERFORM assert_eq(snapshot#>'{3,data,tickets}','[]'::jsonb,'cancellation retains empty current tickets snapshot');
 PERFORM assert_eq(snapshot#>>'{3,created_by}',x->>'actor','cancellation retains actor');
 PERFORM assert_eq(snapshot->0,original->0,'cancellation never rewrites old snapshots');
 PERFORM assert_eq(snapshot->1,edited->1,'cancellation preserves edit history');
 PERFORM assert_eq(snapshot->2,delivered->2,'cancellation preserves delivery history');
 SET LOCAL ROLE authenticated;
 result:=public.storno_order_client_sync_v1(oid,cancel_command);
 result:=public.storno_order_client_sync_v1(oid,gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(pg_temp.payment_history(oid),snapshot,'repeated cancellation appends no history');
 PERFORM pg_temp.adopt_public_link_fixtures();
 SET LOCAL ROLE authenticated;
 result:=public.get_orders(x->>'link',NULL,'{"include_orders_history":true,"include_full_order_data":true}');
 RESET ROLE;
 PERFORM assert_eq(result->>'code','200'::text,'history remains readable through the administration API');
 PERFORM assert_eq(jsonb_array_length(result#>'{data,orders_history}'),4,'administration returns all lifecycle snapshots');
 FOR row_json IN SELECT value FROM jsonb_array_elements(snapshot) LOOP
  SELECT value INTO STRICT projected FROM jsonb_array_elements(result#>'{data,orders_history}')
  WHERE value->>'id'=row_json->>'id';
  PERFORM assert_eq(projected->'data',row_json->'data','API preserves historical answers and products');
  PERFORM assert_eq(projected->'state',row_json->'state','API preserves historical state');
  PERFORM assert_eq(projected->'price',row_json->'price','API preserves historical price');
  PERFORM assert_eq(projected->'currency_code',row_json->'currency_code','API preserves historical currency including legacy null');
  PERFORM assert_eq(projected->'created_by',row_json->'created_by','API preserves historical author');
  PERFORM assert_eq((projected->>'created_at')::timestamptz,(row_json->>'created_at')::timestamptz,'API preserves historical timestamp');
  PERFORM assert_eq(projected->>'order_symbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),'API retains stable order identity');
 END LOOP;
END $$;
