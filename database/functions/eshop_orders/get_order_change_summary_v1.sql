-- Internal read model shared by the editor preview and email preparation.
CREATE OR REPLACE FUNCTION public.get_order_change_summary_v1(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
 v_current jsonb; v_currency text; v_current_price numeric; v_reference eshop.orders_history; v_latest bigint;
 v_sent_at timestamptz; v_ref_tickets jsonb; v_cur_tickets jsonb;
 v_ref jsonb; v_cur jsonb; v_ticket jsonb; v_symbol text; v_state text;
 v_before jsonb; v_after jsonb; v_added jsonb; v_removed jsonb; v_changed jsonb;
 v_cancelled jsonb:='[]'; v_removed_tickets jsonb:='[]'; v_added_tickets jsonb:='[]';
 v_product_changes jsonb:='[]'; v_old_total numeric:=0; v_new_total numeric:=0;
 i integer; j integer; v_has_changes boolean;
BEGIN
 SELECT data,currency_code,price INTO v_current,v_currency,v_current_price FROM eshop.orders WHERE id=p_order_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
 SELECT id INTO v_latest FROM eshop.orders_history WHERE "order"=p_order_id
 ORDER BY created_at DESC,id DESC LIMIT 1;
 SELECT * INTO v_reference FROM eshop.orders_history WHERE "order"=p_order_id
 AND data->>'is_sent_to_customer'='true' ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN v_sent_at:=v_reference.created_at;
 ELSE
  SELECT * INTO v_reference FROM eshop.orders_history WHERE "order"=p_order_id
  ORDER BY created_at ASC,id ASC LIMIT 1;
 END IF;
 v_ref_tickets:=coalesce(v_reference.data->'tickets','[]');
 v_cur_tickets:=coalesce(v_current->'tickets','[]');
 SELECT coalesce(sum(coalesce((p->>'price')::numeric,0)),0) INTO v_old_total
 FROM jsonb_array_elements(v_ref_tickets) t,jsonb_array_elements(coalesce(t->'products','[]')) p;
 SELECT coalesce(sum(coalesce((p->>'price')::numeric,0)),0) INTO v_new_total
 FROM jsonb_array_elements(v_cur_tickets) t,jsonb_array_elements(coalesce(t->'products','[]')) p;
 v_old_total:=coalesce(v_reference.price,v_old_total);
 v_new_total:=coalesce(v_current_price,v_new_total);
 -- Without history there is no evidence from which to invent a change.
 IF v_reference.id IS NOT NULL THEN
  FOR v_ref IN SELECT value FROM jsonb_array_elements(v_ref_tickets) LOOP
   SELECT value INTO v_cur FROM jsonb_array_elements(v_cur_tickets)
   WHERE (v_ref->>'id' IS NOT NULL AND value->>'id'=v_ref->>'id')
      OR (v_ref->>'id' IS NULL AND value=v_ref) LIMIT 1;
   v_symbol:=NULL; v_state:=NULL;
   -- Order membership prevents historical/foreign IDs leaking ticket metadata.
   SELECT t.ticket_symbol,t.state INTO v_symbol,v_state FROM eshop.tickets t
   WHERE t.id::text=v_ref->>'id' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket opt
      WHERE opt.ticket=t.id AND opt."order"=p_order_id);
   v_ticket:=jsonb_build_object('id',v_ref->'id','ticket_symbol',
     coalesce(nullif(v_ref->>'ticket_symbol',''),v_symbol),'products',coalesce(v_ref->'products','[]'));
   IF v_cur IS NULL THEN
    IF v_state='storno' THEN v_cancelled:=v_cancelled||jsonb_build_array(v_ticket);
    ELSE v_removed_tickets:=v_removed_tickets||jsonb_build_array(v_ticket); END IF;
    CONTINUE;
   END IF;
   v_before:=coalesce(v_ref->'products','[]'); v_after:=coalesce(v_cur->'products','[]');
   v_added:='[]'; v_removed:='[]'; v_changed:='[]';
   -- Preserve duplicate instances; never pair products across different tickets.
   IF jsonb_array_length(v_after)>0 THEN
    FOR i IN REVERSE jsonb_array_length(v_after)-1..0 LOOP
     SELECT ordinality::integer-1 INTO j FROM jsonb_array_elements(v_before) WITH ORDINALITY
     WHERE value->>'id' IS NOT DISTINCT FROM v_after->i->>'id'
       AND value->>'title' IS NOT DISTINCT FROM v_after->i->>'title'
       AND abs(coalesce((value->>'price')::numeric,0)-coalesce((v_after->i->>'price')::numeric,0))<0.001
     ORDER BY ordinality LIMIT 1;
     IF j IS NOT NULL THEN v_before:=v_before-j; v_after:=v_after-i; END IF;
    END LOOP;
   END IF;
   IF jsonb_array_length(v_after)>0 THEN
    FOR i IN REVERSE jsonb_array_length(v_after)-1..0 LOOP
     SELECT ordinality::integer-1 INTO j FROM jsonb_array_elements(v_before) WITH ORDINALITY
     WHERE value->>'id' IS NOT DISTINCT FROM v_after->i->>'id' ORDER BY ordinality LIMIT 1;
     IF j IS NOT NULL THEN
      v_changed:=v_changed||jsonb_build_array(jsonb_build_object('from',v_before->j,'to',v_after->i));
      v_before:=v_before-j; v_after:=v_after-i;
     END IF;
    END LOOP;
   END IF;
   v_added:=v_after; v_removed:=v_before;
   IF jsonb_array_length(v_added)+jsonb_array_length(v_removed)+jsonb_array_length(v_changed)>0 THEN
    v_product_changes:=v_product_changes||jsonb_build_array(v_ticket||jsonb_build_object(
     'added',v_added,'removed',v_removed,'changed',v_changed));
   END IF;
  END LOOP;
  FOR v_cur IN SELECT value FROM jsonb_array_elements(v_cur_tickets) LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_ref_tickets) r
     WHERE (v_cur->>'id' IS NOT NULL AND r->>'id'=v_cur->>'id') OR (v_cur->>'id' IS NULL AND r=v_cur)) THEN
    v_added_tickets:=v_added_tickets||jsonb_build_array(v_cur);
   END IF;
  END LOOP;
 END IF;
 v_has_changes:=v_reference.id IS NOT NULL AND (jsonb_array_length(v_cancelled)+jsonb_array_length(v_removed_tickets)
   +jsonb_array_length(v_added_tickets)+jsonb_array_length(v_product_changes)>0 OR v_old_total<>v_new_total);
 RETURN jsonb_build_object('version',1,'cancelledTickets',v_cancelled,'removedTickets',v_removed_tickets,
   'addedTickets',v_added_tickets,'productChanges',v_product_changes,'referenceTotal',v_old_total,
   'currentTotal',v_new_total,'currencyCode',coalesce(v_currency,'CZK'),'hasChanges',v_has_changes,'referenceOrder',to_jsonb(v_reference),
   'referenceHistoryId',v_reference.id,'latestHistoryId',v_latest,'latestSentAt',v_sent_at);
END $$;
REVOKE ALL ON FUNCTION public.get_order_change_summary_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_change_summary_v1(bigint) TO service_role;
