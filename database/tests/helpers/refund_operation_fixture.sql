-- Requires payment_lifecycle_fixture.sql in the same disposable connection.
CREATE OR REPLACE FUNCTION pg_temp.refund_fixture()
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x jsonb:=pg_temp.payment_fixture(); account text:='CZ6508000000192000145399'; ns text; bank bigint:=(x->>'bank')::bigint; pi eshop.payment_info; un bigint; con bigint;
BEGIN
 account:=public.canonical_payment_reference_account_internal(bank::text||'/2010');
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 UPDATE eshop.bank_accounts SET account_number=account,supported_currencies=ARRAY['CZK','EUR','USD'] WHERE id=bank;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,(x->>'actor')::uuid,true);
 ns:=encode(extensions.digest(account,'sha256'),'hex');
 INSERT INTO eshop.payment_reference_namespaces(id,canonical_account,allocation_enabled) VALUES(ns,account,true) ON CONFLICT(id) DO NOTHING;
 INSERT INTO eshop.payment_reference_accounts(bank_account_id,namespace_id,account_number_snapshot) VALUES(bank,ns,account);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES((x->>'organization')::bigint,'active',repeat('a',64));
 SELECT * INTO pi FROM eshop.payment_info WHERE id=(x->>'payment')::bigint;
 INSERT INTO eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256,payment_info_id,original_payment_info_id,form_id)
 VALUES(ns,pi.variable_symbol,'refund-test-'||pi.id,'{}',repeat('a',64),pi.id,pi.id,(x->>'form')::bigint);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256,legacy_blocked_at)
 VALUES('refund-test-'||bank,'festapp',bank::text,bank,account,'FIO','api','connected',repeat('a',64),now()) RETURNING id INTO con;
 PERFORM pg_temp.payment_pair(x,1000);
 RETURN x||jsonb_build_object('unit',un,'namespace',ns,'connection',con,'variableSymbol',pi.variable_symbol::text);
END $$;
CREATE OR REPLACE FUNCTION pg_temp.refund_bank_event(x jsonb,sequence_no int,amount_cents int,ref text DEFAULT NULL,p_extra jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE event jsonb; result jsonb; bank text:=x->>'bank';
BEGIN
 event:=jsonb_build_object('event','transaction.received','event_version','2',
  'delivery_id','01K0000000000000000000'||lpad(sequence_no::text,4,'0'),
  'data',jsonb_build_object('id',sequence_no,'bank_account_id',bank,'transaction_id',(900000+sequence_no)::text,
    'amount_cents',amount_cents,'currency','CZK','date',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'direction',CASE WHEN amount_cents<0 THEN 'outgoing' ELSE 'incoming' END,'identity_kind','movement',
    'identity_provenance','fio_api_column22','source','fio_api','raw_vs',coalesce(ref,x->>'variableSymbol'),
    'counter_account','1234','bank_code','2010','transaction_type','bank debit'));
 event:=jsonb_set(event,'{data}',event->'data'||p_extra);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 result:=public.ingest_bank_sync_transaction('refund-test-'||bank,'festapp',repeat('c',64),event);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 RETURN result;
END $$;
