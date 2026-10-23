-- Same bounded administration projection for requirements and final approval.
-- A buyer belongs to one order; do not repeat contact data for every ticket.
CREATE OR REPLACE FUNCTION public.blueprint_order_conflicts_internal(p_analysis jsonb,p_effects jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH tickets AS MATERIALIZED(SELECT c FROM jsonb_array_elements(coalesce(p_analysis->'conflicts','[]')) c),
 grouped AS(SELECT (c->>'order_id')::bigint id,min(c->>'email') email,min(c->>'name') name,min(c->>'surname') surname,
  count(DISTINCT c->>'ticket_id') selected_count,
  jsonb_agg(jsonb_build_object('ticketId',c->'ticket_id','selectedSpotIds',c->'selected_spot_ids',
   'ticketSymbol',c->'ticket_symbol','ticketAmount',c->>'total_price','products',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('productId',p->'id','title',p->'title',
     'amount',p->>'price','currencyCode',upper(btrim(p->>'currency_code')))),'[]')
     FROM jsonb_array_elements(CASE WHEN jsonb_typeof(c->'products')='array' THEN c->'products' ELSE '[]'::jsonb END) p))
   ORDER BY (c->>'ticket_id')::bigint) rows
 FROM tickets GROUP BY (c->>'order_id')::bigint),
 money AS MATERIALIZED(SELECT (e->>'orderId')::bigint id,e->>'afterState' state FROM jsonb_array_elements(coalesce(p_effects,'[]')) e)
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',g.id,'selectedTicketCount',g.selected_count,
  'stateAfter',m.state,'customer',jsonb_build_object('email',g.email,'name',g.name,'surname',g.surname),
  'tickets',g.rows) ORDER BY g.id),'[]') FROM grouped g LEFT JOIN money m ON m.id=g.id
$$;
REVOKE ALL ON FUNCTION public.blueprint_order_conflicts_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
