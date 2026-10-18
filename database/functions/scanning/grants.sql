-- Explicit grants; internal primitives never callable via PostgREST.
REVOKE ALL ON FUNCTION public.scanner_default_settings_internal(bigint),public.scanner_validate_settings_internal(bigint,jsonb),
 public.scanner_ticket_projection_internal(bigint,jsonb,bigint),public.scanner_session_internal(uuid,text,boolean),public.scanner_lock_ticket_internal(bigint),public.scanner_admit_ticket_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_settings(bigint),public.update_scanner_settings(bigint,bigint,jsonb),public.resolve_scanner_conflict(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_scanner_settings(bigint),public.update_scanner_settings(bigint,bigint,jsonb),public.resolve_scanner_conflict(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.open_scanner_session(text,bigint,text),public.revoke_scanner_session(uuid,text),public.lookup_scanner_ticket(uuid,text,text),
 public.search_scanner_tickets(uuid,text,text,bigint),public.sync_scanner_operations(uuid,text,jsonb),public.get_scanner_receipts(uuid,text,uuid[]),
 public.get_scanner_summary(uuid,text),public.prepare_scanner_snapshot(uuid,text),public.get_scanner_snapshot_page(uuid,text,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_scanner_session(text,bigint,text),public.revoke_scanner_session(uuid,text),public.lookup_scanner_ticket(uuid,text,text),
 public.search_scanner_tickets(uuid,text,text,bigint),public.sync_scanner_operations(uuid,text,jsonb),public.get_scanner_receipts(uuid,text,uuid[]),
 public.get_scanner_summary(uuid,text),public.prepare_scanner_snapshot(uuid,text),public.get_scanner_snapshot_page(uuid,text,uuid,integer) TO anon,authenticated;
-- Seed only existing actions, with their own field references and original price policy.
INSERT INTO public.scanner_settings(occasion_id,config) SELECT id,public.scanner_default_settings_internal(id) FROM public.occasions ON CONFLICT DO NOTHING;

-- One-time migration of the previous occasion-specific presentation.
UPDATE public.scanner_settings s SET config=jsonb_set(s.config,'{sensitive,price}','false')
 FROM public.occasions o WHERE o.id=s.occasion_id AND o.link='r48vetrkovice2026' AND s.revision=1;
UPDATE public.scanner_settings s SET config=jsonb_set(s.config,'{fields}',x.fields)
 FROM (SELECT fm.occasion,jsonb_agg(jsonb_build_object('key','order:'||f.form||':'||f.id,'source','order_field',
 'form_id',f.form,'field_id',f.id,'label',f.title,'default_visible',true,'hide_empty',true) ORDER BY f.id) fields
 FROM public.form_fields f JOIN public.forms fm ON fm.id=f.form WHERE NOT f.is_ticket_field AND f.id IN(735,725,739,615,616,629,620) GROUP BY fm.occasion) x
 WHERE x.occasion=s.occasion_id AND s.revision=1;
