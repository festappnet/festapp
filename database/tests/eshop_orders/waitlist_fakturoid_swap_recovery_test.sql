-- Regression: invoice preparation rollback restores pre-swap slots and preserves
-- source-side actions performed while the selected target is preparing.
DO $$
DECLARE org bigint; un bigint; oc bigint; form_id bigint; form_key uuid; account_id bigint; type_id bigint; product_id bigint;
 source_id bigint; target_id bigint; actor uuid; offer uuid; slot_a uuid; slot_b uuid; person_a uuid; person_b uuid; remainder uuid;
 command uuid; client uuid:=gen_random_uuid(); result jsonb; input jsonb; scenario text; before_answers jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('festapp.email_wake','scheduled',true);
 SELECT id INTO actor FROM auth.users LIMIT 1;
 FOREACH scenario IN ARRAY ARRAY['split_swap','split_withdraw_displaced','split_withdraw_other','split_edit_displaced','full_permutation','expiry_swap'] LOOP
  PERFORM set_config('request.jwt.claim.sub','',true);
  INSERT INTO organizations(title) VALUES('Waitlist recovery '||scenario) RETURNING id INTO org;
  INSERT INTO units(title,organization) VALUES('Recovery unit',org) RETURNING id INTO un;
  INSERT INTO occasions(title,unit,organization,link,start_time,end_time)
   VALUES('Recovery occasion',un,org,'recovery-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(oc,actor,true,true);
  INSERT INTO forms(occasion,link,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds)
   VALUES(oc,'recovery-'||gen_random_uuid(),2,true,3600) RETURNING id,key INTO form_id,form_key;
  INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Recovery account','FIO',ARRAY['CZK']) RETURNING id INTO account_id;
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,account_id);
  INSERT INTO eshop.product_types(title,type,occasion) VALUES('Admission','spot',oc) RETURNING id INTO type_id;
  INSERT INTO eshop.products(title,product_type,price,currency_code,occasion) VALUES('Admission',type_id,100,'CZK',oc) RETURNING id INTO product_id;
  INSERT INTO form_fields(form,product_type,type) VALUES(form_id,type_id,'product_type');
  INSERT INTO eshop.external_services(unit,type,data) VALUES(un,'FAKTUROID','{}');
  source_id:=public.allocate_ticket_order_identity_internal(form_id);
  UPDATE eshop.orders SET state='waitlisted',price=NULL,data=jsonb_build_object('form',form_key,'email','recovery@example.invalid') WHERE id=source_id;
  INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,lifecycle,answers)
   VALUES(source_id,source_id,form_id,'offered','{"original":"A"}') RETURNING id INTO person_a;
  INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,lifecycle,answers)
   VALUES(source_id,source_id,form_id,CASE WHEN scenario='full_permutation' THEN 'offered' ELSE 'waiting' END,'{"original":"B"}') RETURNING id INTO person_b;
  IF scenario<>'full_permutation' THEN
   INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,lifecycle,answers)
    VALUES(source_id,source_id,form_id,'waiting','{"original":"remainder"}') RETURNING id INTO remainder;
  END IF;
  INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision)
   VALUES(source_id,form_id,actor,clock_timestamp()+interval '1 hour',0) RETURNING id INTO offer;
  INSERT INTO eshop.waitlist_offer_slots(offer_id,participant_id,form_id) VALUES(offer,person_a,form_id) RETURNING id INTO slot_a;
  IF scenario='full_permutation' THEN
   INSERT INTO eshop.waitlist_offer_slots(offer_id,participant_id,form_id) VALUES(offer,person_b,form_id) RETURNING id INTO slot_b;
   -- Deliberately bind descending persons to ascending slots so canonical accept
   -- ordering changes the binding even when every person is selected.
   UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id IN(slot_a,slot_b);
   UPDATE eshop.waitlist_offer_slots SET participant_id=CASE WHEN id=least(slot_a,slot_b) THEN greatest(person_a,person_b) ELSE least(person_a,person_b) END,
     outcome='pending' WHERE id IN(slot_a,slot_b);
   SELECT id INTO slot_a FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND participant_id=person_a;
   SELECT id INTO slot_b FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND participant_id=person_b;
  END IF;
  input:=jsonb_build_object('form',form_key,'email','recovery@example.invalid','ticket',jsonb_build_array(
   jsonb_build_object('participantId',person_b,'fields',jsonb_build_array(jsonb_build_object('product_type',product_id)))));
  IF scenario='full_permutation' THEN input:=jsonb_set(input,'{ticket}',input->'ticket'||jsonb_build_array(
   jsonb_build_object('participantId',person_a,'fields',jsonb_build_array(jsonb_build_object('product_type',product_id))))); END IF;
  command:=gen_random_uuid();
  result:=public.execute_waitlist_command_client_sync_v1('accept',jsonb_build_object('offerId',offer,
   'personIds',CASE WHEN scenario='full_permutation' THEN jsonb_build_array(person_b,person_a) ELSE jsonb_build_array(person_b) END,
   'orderDetails',input),command,client,actor);
  IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION '% acceptance failed: %',scenario,result; END IF;
  target_id:=(result#>>'{data,order,id}')::bigint;
  PERFORM assert_eq((SELECT previous_slots->0->>'outcome' FROM eshop.waitlist_acceptance_attempts WHERE command_id=command),'pending','Journal stores pre-swap pending outcome');
  IF scenario='split_withdraw_displaced' OR scenario='split_withdraw_other' THEN
   result:=public.execute_waitlist_command_client_sync_v1('withdraw',jsonb_build_object('orderId',source_id,
    'personIds',jsonb_build_array(CASE WHEN scenario='split_withdraw_displaced' THEN person_a ELSE remainder END)),gen_random_uuid(),client,actor);
   IF result#>>'{data,code}' IS DISTINCT FROM '200' THEN RAISE EXCEPTION '% concurrent withdrawal failed: %',scenario,result; END IF;
  ELSIF scenario='split_edit_displaced' THEN
   -- Another source-side editor changes a person's answers during preparation.
   UPDATE eshop.order_participants SET answers='{"edited":"preserve"}',updated_at=clock_timestamp() WHERE id=person_a;
  ELSIF scenario='expiry_swap' THEN
   UPDATE eshop.waitlist_offers SET expires_at=clock_timestamp()-interval '1 second',created_at=clock_timestamp()-interval '2 hours' WHERE id=offer;
  END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM public.abort_fakturoid_ticket_order_v1(target_id,command);
  PERFORM public.abort_fakturoid_ticket_order_v1(target_id,command);
  PERFORM assert_eq((SELECT participant_id FROM eshop.waitlist_offer_slots WHERE id=slot_a),person_a,'Abort restores original slot/person binding');
  PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=person_b),CASE WHEN scenario='full_permutation' THEN 'offered' ELSE 'waiting' END,'Selected person returns to exact prior lifecycle');
  PERFORM assert_eq((SELECT current_order_id FROM eshop.order_participants WHERE id=person_b),source_id,'Selected person returns to source');
  IF scenario='split_withdraw_displaced' THEN
   PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=person_a),'withdrawn','Displaced withdrawal survives abort');
   PERFORM assert_eq((SELECT outcome FROM eshop.waitlist_offer_slots WHERE id=slot_a),'cancelled','Withdrawn person cannot regain a reservation');
  ELSIF scenario='expiry_swap' THEN
   PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=person_a),'offer_expired','Original offered person expires');
   PERFORM assert_eq((SELECT outcome FROM eshop.waitlist_offer_slots WHERE id=slot_a),'expired','Expired offer cannot regain a reservation');
  ELSE
   PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=person_a),'offered','Original offered person regains offer');
   PERFORM assert_eq((SELECT outcome FROM eshop.waitlist_offer_slots WHERE id=slot_a),'pending','Original unexpired slot restored pending');
  END IF;
  IF scenario='split_withdraw_other' THEN
   PERFORM assert_eq((SELECT lifecycle FROM eshop.order_participants WHERE id=remainder),'withdrawn','Unrelated remainder withdrawal survives abort');
  ELSIF scenario='split_edit_displaced' THEN
   PERFORM assert_eq((SELECT answers FROM eshop.order_participants WHERE id=person_a),'{"edited":"preserve"}'::jsonb,'Concurrent displaced answer edit survives abort');
  ELSIF scenario='full_permutation' THEN
   PERFORM assert_eq(target_id,source_id,'Full conversion keeps identity');
   PERFORM assert_eq((SELECT participant_id FROM eshop.waitlist_offer_slots WHERE id=slot_b),person_b,'Full abort restores second original binding');
  END IF;
 END LOOP;
END $$;
