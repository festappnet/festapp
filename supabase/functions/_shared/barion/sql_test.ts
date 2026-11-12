import { strict as assert } from "node:assert";
import { barionFacts } from "./facts.ts";
import success from "./fixtures/succeeded.json" with { type: "json" };
import partial from "./fixtures/partial-refund.json" with { type: "json" };
import full from "./fixtures/full-refund.json" with { type: "json" };
const snapshot = {
  attemptId: success.PaymentRequestId,
  accountId: "4df06591ac0e4369998e24783d09cfaf",
  livemode: false,
  amountMinor: 100,
  currency: "CZK",
  orderReference: "Sandbox",
  createdAt: Math.floor(Date.parse("2026-11-06T12:18:38Z") / 1000),
  expiresAt: Math.floor(Date.parse("2026-11-06T12:49:38Z") / 1000),
  idempotencyKey: success.PaymentRequestId,
};
const literal = (value: unknown) =>
  "'" + JSON.stringify(value).replaceAll("'", "''") + "'::jsonb";
Deno.test({
  name:
    "Barion recorded real protocol reaches disposable SQL owner with refund/replay/hold/late-payment and ACL",
  ignore: !Deno.env.get("BARION_DATABASE_URL"),
  fn: async () => {
    const db = Deno.env.get("BARION_DATABASE_URL")!, url = new URL(db);
    assert(["127.0.0.1", "localhost", "[::1]"].includes(url.hostname));
    let setup = "";
    for (
      const path of [
        "database/tests/helpers/assertions.sql",
        "database/tests/helpers/payment_lifecycle_fixture.sql",
        "database/tests/scanning/fixture.sql",
      ]
    ) setup += await Deno.readTextFile(path) + "\n";
    const paid = literal(barionFacts(snapshot, success.PaymentId, success)),
      refund = literal(barionFacts(snapshot, partial.PaymentId, partial)),
      fullRefund = literal(barionFacts(snapshot, full.PaymentId, full));
    const script =
      `BEGIN; SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL festapp.email_wake='scheduled';
 DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project LIKE 'festapp-%') THEN RAISE EXCEPTION 'wrong disposable target'; END IF; END $$;
 ${setup}
 SET LOCAL request.jwt.claim.role='service_role';
 DO $$ DECLARE fx jsonb:=public.scanner_test_fixture(1); t bigint:=(fx#>>'{tickets,0}')::bigint;
 oid bigint; pi bigint; org bigint; u bigint; a uuid:='${snapshot.attemptId}'; c uuid:=extensions.gen_random_uuid();
 claim jsonb; lease uuid; r jsonb; v bigint; oc bigint:=(fx->>'occasion')::bigint;
 BEGIN
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE ticket=t;
 SELECT organization,unit INTO org,u FROM public.occasions WHERE id=oc;
 INSERT INTO eshop.barion_connections(id,organization_id,unit_id,account_id,enabled,business_name,sandbox_form_ids)
 VALUES(c,org,u,'${snapshot.accountId}',true,'Testovací pořadatel',ARRAY[(fx->>'form')::bigint]);
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,barion_connection_id) VALUES(1,'CZK','barion',c) RETURNING id INTO pi;
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'providerConnections',jsonb_build_object('barion',c))) WHERE id=(fx->>'form')::bigint;
 UPDATE eshop.payment_info SET deadline=clock_timestamp()+interval '20 minutes' WHERE id=pi;
 UPDATE eshop.orders SET payment_info=pi,price=1,currency_code='CZK',state='ordered' WHERE id=oid;
 UPDATE eshop.tickets SET state='ordered' WHERE id=t;
 PERFORM assert_eq(public.provider_paid_guard_internal(oid)->>'code','409','missing Barion attempt cannot authorize manual paid');
 INSERT INTO eshop.barion_attempts(id,order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,created_at,reservation_expires_at,return_base_url,remote_id)
 VALUES(a,oid,pi,org,u,c,100,'CZK','2026-11-06T12:18:38Z','2026-11-06T12:49:38Z','https://tickets.example.test/payments/barion/return','${success.PaymentId}');
 PERFORM assert_true(NOT public.provider_ticket_admission_allowed_internal(t),'unpaid Barion ticket denied');
 -- Durable checkout dispatch is single-shot even when its response is lost.
 UPDATE eshop.barion_attempts SET remote_id=NULL,reservation_expires_at=clock_timestamp()+interval '20 minutes' WHERE id=a;
 PERFORM public.barion_payment_provider_internal('attach_source',jsonb_build_object('orderId',oid,'commandId',extensions.gen_random_uuid(),
  'source',jsonb_build_object('tokenHash',encode(extensions.digest(repeat('a',64),'sha256'),'hex'),'returnHash',encode(extensions.digest(repeat('b',64),'sha256'),'hex'),
   'contentHash',repeat('c',64),'sealed',jsonb_build_object('v',1,'iv','fixture','ciphertext','fixture'))));
 UPDATE eshop.barion_connections SET enabled=false WHERE id=c;
 claim:=public.barion_runtime_internal('claim_checkout',jsonb_build_object('token',repeat('a',64)));
 PERFORM assert_eq(claim->>'disposition','read','sandbox technical gate still blocks collection');
 UPDATE eshop.barion_connections SET enabled=true WHERE id=c;
 INSERT INTO eshop.unit_payment_method_policies(unit_id,method,mode) VALUES(u,'barion','disabled');
 claim:=public.barion_runtime_internal('claim_checkout',jsonb_build_object('token',repeat('a',64)));
 PERFORM assert_eq(claim->>'disposition','read','sandbox cannot bypass the product policy');
 PERFORM assert_true((SELECT dispatched_at IS NULL FROM eshop.barion_attempts WHERE id=a),'blocked attempts create no dispatch');
 DELETE FROM eshop.unit_payment_method_policies WHERE unit_id=u AND method='barion';
 claim:=public.barion_runtime_internal('claim_checkout',jsonb_build_object('token',repeat('a',64)));
 PERFORM assert_eq(claim->>'disposition','dispatch','first dispatch is durably fenced');
 lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('commit_checkout',jsonb_build_object('attemptId',a,'lease',lease,'checkout',jsonb_build_object('id','${success.PaymentId}','url','https://secure.test.barion.com/Pay?Id=${success.PaymentId}',
  'expiresAt',(SELECT extract(epoch FROM reservation_expires_at)::bigint FROM eshop.barion_attempts WHERE id=a))));
 PERFORM assert_eq(r#>>'{payment,status}','open','canonical remote checkout committed through store');
 -- Reset only this disposable fixture to separately exercise a lost response.
 UPDATE eshop.barion_attempts SET remote_id=NULL,state='preparing',dispatched_at=NULL WHERE id=a;
 claim:=public.barion_runtime_internal('claim_checkout',jsonb_build_object('token',repeat('a',64)));lease:=(claim->>'lease')::uuid;
 PERFORM public.barion_runtime_internal('fail',jsonb_build_object('attemptId',a,'lease',lease));
 claim:=public.barion_runtime_internal('claim_checkout',jsonb_build_object('token',repeat('a',64)));
 PERFORM assert_true(claim->>'disposition' IN ('read','busy'),'lost response never creates another remote payment');
 PERFORM assert_true((SELECT dispatched_at IS NOT NULL FROM eshop.barion_attempts WHERE id=a),'dispatch intent retained');
 INSERT INTO eshop.unit_payment_method_policies(unit_id,method,mode) VALUES(u,'barion','disabled');
 BEGIN PERFORM public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','foreign'));RAISE EXCEPTION 'foreign account accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BARION_SCOPE_INVALID' THEN RAISE; END IF; END;
 UPDATE eshop.barion_attempts SET remote_id='${success.PaymentId}',state='open' WHERE id=a;

 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}')); lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${paid}));
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','real normalized Barion facts use shared paid owner');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),1::numeric,'customer received excludes processing fee');
 PERFORM assert_true(public.provider_ticket_admission_allowed_internal(t),'settled admission allowed');
 -- A current valid lease is mandatory even for identical financial replay.
 BEGIN PERFORM public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${paid}));RAISE EXCEPTION 'stale accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BARION_LEASE_LOST' THEN RAISE; END IF; END;
 SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 UPDATE eshop.barion_attempts SET last_synced_at=NULL WHERE id=a;
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}'));lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${paid}));
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v,'duplicate callback facts have no second email consequence');
 UPDATE eshop.barion_attempts SET last_synced_at=NULL WHERE id=a;
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}'));lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${refund}));
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),0.5::numeric,'external partial refund stored');
 PERFORM assert_eq(r#>>'{payment,status}','partially_refunded','refund does not depend on PaymentStatus changing');
 -- An incomplete history cannot erase a previously confirmed refund; it holds admission.
 UPDATE eshop.barion_attempts SET last_synced_at=NULL WHERE id=a;
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}'));lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${paid}));
 PERFORM assert_true(NOT public.provider_ticket_admission_allowed_internal(t),'missing old refund creates hold');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),0.5::numeric,'stored refund retained');
 -- The independently observed full refund uses the same common storno owner.
 UPDATE eshop.barion_attempts SET last_synced_at=NULL WHERE id=a;
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}'));lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${fullRefund}));
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','real full refund reaches common storno owner');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=t),'storno','refunded ticket cancelled');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),1::numeric,'real full refund totals');
 -- Release inventory for unresolved create without declaring financial absence.
 DELETE FROM eshop.barion_movements WHERE attempt_id=a; DELETE FROM eshop.barion_observations WHERE attempt_id=a;
 UPDATE eshop.barion_attempts SET financial_hold=false,state='uncertain',remote_id=NULL,last_synced_at=NULL,dispatched_at=clock_timestamp()-interval '2 minutes',reservation_expires_at=clock_timestamp()-interval '1 minute' WHERE id=a;
 UPDATE eshop.orders SET state='ordered' WHERE id=oid; UPDATE eshop.tickets SET state='ordered' WHERE id=t;
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}'));lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('defer',jsonb_build_object('attemptId',a,'lease',lease,'seconds',120));
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','unresolved inventory released');
 PERFORM assert_eq((SELECT state FROM eshop.barion_attempts WHERE id=a),'uncertain','finance uncertainty retained');
 -- Late notification cannot restore released seats even if the payment itself completed in time.
 claim:=public.barion_runtime_internal('claim_sync',jsonb_build_object('attemptId',a,'accountId','${snapshot.accountId}'));lease:=(claim->>'lease')::uuid;
 r:=public.barion_runtime_internal('ingest',jsonb_build_object('attemptId',a,'lease',lease,'facts',${paid}));
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','late observation never revives seats');
 PERFORM assert_eq(r#>>'{payment,status}','action_required','late observation held for operator');
 PERFORM assert_true(NOT has_function_privilege('anon','public.barion_runtime_internal(text,jsonb)','EXECUTE'),'anon has no service mutation access');
 PERFORM assert_true(NOT has_table_privilege('service_role','eshop.barion_movements','INSERT'),'no direct service movement writes');
 END $$; ROLLBACK;`;
    const result = await new Deno.Command("psql", {
      args: [db, "-X", "-v", "ON_ERROR_STOP=1", "-q"],
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    const writer = result.stdin.getWriter();
    await writer.write(new TextEncoder().encode(script));
    await writer.close();
    const output = await result.output();
    assert.equal(output.code, 0, new TextDecoder().decode(output.stderr));
  },
});
