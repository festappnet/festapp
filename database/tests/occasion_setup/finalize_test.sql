-- Exercise canonical source -> draft -> finalizer, completion receipts and rollback.
DO $$
DECLARE actor uuid; org bigint; target bigint; source_id bigint; source_type bigint; source_product bigint;
 plan bigint; seat bigint; source_node_id uuid:=gen_random_uuid(); form_id bigint; d jsonb; source jsonb; payload jsonb; response jsonb; command uuid:=gen_random_uuid();
 draft_id uuid:=gen_random_uuid(); new_id bigint; new_type bigint; before_count bigint; layout jsonb;
BEGIN
 -- Own scopes avoid interference with concurrent local QA and its rate budget.
 PERFORM create_user_for_test('setup-finalizer','setup-finalizer-'||gen_random_uuid()||'@example.invalid');
 actor:=get_user_id('setup-finalizer');
 INSERT INTO public.organizations(title) VALUES('Setup finalizer test') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Setup finalizer unit',org) RETURNING id INTO target;
 INSERT INTO public.unit_users("user",unit,is_editor,is_manager) VALUES(actor,target,true,true);
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,target,'Finalize source','source-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO source_id;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(source_id,'Seats','spot') RETURNING id INTO source_type;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
 VALUES(source_id,source_type,'Admission',690,'CZK') RETURNING id INTO source_product;
 INSERT INTO eshop.blueprints(occasion,organization,title,configuration,groups)
 VALUES(source_id,org,'Hall','{"dimensions":{"width":33,"height":8}}','[]') RETURNING id INTO plan;
 INSERT INTO eshop.spots(occasion,blueprint,product,title,secret,secret_expiration_time)
 VALUES(source_id,plan,source_product,'A1',gen_random_uuid(),now()+interval '1 day') RETURNING id INTO seat;
 UPDATE eshop.blueprints SET layout=jsonb_build_object('schemaVersion',2,'symbolSetVersion',1,
 'canvas',jsonb_build_object('x',0,'y',0,'width',1000,'height',1000,'fill','#ffffffff'),
 'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,'textPolicy',jsonb_build_object('language','und','direction','auto'),
 'nodes',jsonb_build_array(jsonb_build_object('id',source_node_id,'kind','seat','width',40,'height',40,
 'transform',jsonb_build_object('x',60,'y',60,'rotation',0)))),layout_revision=1 WHERE id=plan;
 INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot) VALUES(plan,source_node_id,seat);
 INSERT INTO public.forms(occasion,title,link,blueprint,is_open)
 VALUES(source_id,'Registration','form-'||gen_random_uuid(),plan,true) RETURNING id INTO form_id;
 INSERT INTO public.form_fields(form,title,type,product_type,"order") VALUES(form_id,'Seats','product_type',source_type,0);
 INSERT INTO public.form_fields(form,title,type,"order") VALUES(form_id,'Ticket','ticket',1);
 layout:=jsonb_build_object('schemaVersion',3,'templates',jsonb_build_object('wide',jsonb_build_object(
 'page',jsonb_build_object('width',595.28,'height',841.89),'ticketArea',jsonb_build_object('x',0,'y',0,'width',500,'height',300),
 'elements',jsonb_build_array(
 jsonb_build_object('id','qr','binding','qr','box',jsonb_build_object('x',0,'y',0,'width',80,'height',80),'visible',true,'locked',false,'style',jsonb_build_object('fontSize',12,'minFontSize',6,'maxLines',1,'color','000000','align','left')),
 jsonb_build_object('id','symbol','binding','ticketSymbol','box',jsonb_build_object('x',0,'y',90,'width',200,'height',30),'visible',true,'locked',false,'style',jsonb_build_object('fontSize',12,'minFontSize',6,'maxLines',1,'color','000000','align','left')),
 jsonb_build_object('id','seatProduct','binding','productType','productTypeId',source_type,'label','Seat','box',jsonb_build_object('x',0,'y',130,'width',200,'height',30),'visible',true,'locked',false,'style',jsonb_build_object('fontSize',12,'minFontSize',6,'maxLines',1,'color','000000','align','left'))))));
 UPDATE public.occasions SET features=jsonb_build_array(jsonb_build_object('code','ticket','is_enabled',true,'layout',layout)) WHERE id=source_id;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT x INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(target)) x WHERE (x->'occasion'->>'id')::bigint=source_id;
 PERFORM assert_false((source->'blueprints')::text LIKE '%secret%' OR (source->'blueprints')::text LIKE '%spotId%' OR (source->'blueprints')::text LIKE '%order_product_ticket%','Source has no occupancy or runtime identities');
 d:=public.create_occasion_setup_draft(draft_id,target);
 payload:=jsonb_build_object('title','Finalized copy','link','copy-'||draft_id,'start',now()+interval '1 month','end',now()+interval '32 days',
 'sourceId',source_id,'reviewConfirmed',true,'formEnabled',true,'formDraft',(source->'forms'->0)||'{"link":""}',
 'ticketDraft',jsonb_build_object('code','ticket','is_enabled',true,'layout',layout),
 'blueprintMode','Převzít','blueprintLayoutDraft',source#>'{blueprints,0,blueprintLayoutDraft}');
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 EXECUTE 'RESET ROLE';
 SELECT count(*) INTO before_count FROM public.occasions;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN
  PERFORM public.finalize_occasion_setup_draft(draft_id,1,command);
  RAISE EXCEPTION 'Stale finalization accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 response:=public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command);
 new_id:=(response->'data'->>'occasionId')::bigint;
 PERFORM assert_eq(public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command),response,'Same-command replay');
 PERFORM assert_eq(public.finalize_occasion_setup_draft(draft_id,1,gen_random_uuid()),response,'Retry with another command retains receipt');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_occasion_setup_drafts(target)) x WHERE x->>'id'=draft_id::text),'Finalized draft is not resumable');
 PERFORM assert_eq(public.get_occasion_setup_draft(draft_id)->'data'->'finalizeResponse',response,'Stale open page can read terminal receipt');
 BEGIN PERFORM public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5); RAISE EXCEPTION 'Finalized save accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions),before_count+1,'Exactly one event');
 PERFORM assert_true((SELECT is_hidden AND NOT is_open FROM public.occasions WHERE id=new_id),'New event hidden and closed');
 PERFORM assert_true((SELECT NOT is_open FROM public.forms WHERE occasion=new_id),'Form closed');
 PERFORM assert_eq((SELECT count(*) FROM eshop.spots WHERE occasion=new_id),1::bigint,'All seats copied');
 PERFORM assert_true((SELECT bool_and(s.id<>seat AND s.product<>source_product AND p.occasion=new_id AND s.secret IS NULL AND s.secret_expiration_time IS NULL AND s.order_product_ticket IS NULL) FROM eshop.spots s JOIN eshop.products p ON p.id=s.product WHERE s.occasion=new_id),'New seat/product identities and no occupancy');
 SELECT product_type INTO new_type FROM eshop.products WHERE occasion=new_id LIMIT 1;
 PERFORM assert_eq((SELECT f->'layout'->'templates'->'wide'->'elements'->2->>'productTypeId' FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_id AND f->>'code'='ticket'),new_type::text,'Ticket product type rebound');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE occasion=new_id),0::bigint,'No orders copied');
 PERFORM assert_true((SELECT sb.node_id<>source_node_id FROM eshop.blueprint_seat_bindings sb JOIN eshop.blueprints bp ON bp.id=sb.blueprint WHERE bp.occasion=new_id),'New layout node identity');
 -- Fail after aggregate creation: the entire operation and command must roll back.
 EXECUTE 'SET LOCAL ROLE authenticated';
 draft_id:=gen_random_uuid(); command:=gen_random_uuid();
 d:=public.create_occasion_setup_draft(draft_id,target);
 payload:=jsonb_set(payload,'{ticketDraft,layout,schemaVersion}','1');
 payload:=jsonb_set(payload,'{link}',to_jsonb('invalid-'||draft_id));
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 BEGIN
  PERFORM public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command);
  RAISE EXCEPTION 'Invalid schema accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Invalid ticket layout' THEN RAISE; END IF; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions),before_count+1,'Late validation failure rolls back event');
 PERFORM assert_false((SELECT data ? 'finalizedOccasion' FROM public.occasion_setup_drafts WHERE id=draft_id),'Failed draft remains editable');
 EXECUTE 'SET LOCAL ROLE authenticated';
 payload:=jsonb_set(payload,'{ticketDraft,layout,schemaVersion}','3');
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command);
 PERFORM assert_eq(response->>'status','applied','Failed command can retry after correction');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions),before_count+2,'Corrected retry commits exactly one event');

 -- Stable mode none ignores an imported layout while retaining normal products.
 EXECUTE 'SET LOCAL ROLE authenticated';
 draft_id:=gen_random_uuid(); command:=gen_random_uuid();
 d:=public.create_occasion_setup_draft(draft_id,target);
 payload:=payload||jsonb_build_object('blueprintMode','none','link','no-plan-'||draft_id);
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command);
 new_id:=(response->'data'->>'occasionId')::bigint;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM eshop.blueprints WHERE occasion=new_id),0::bigint,'None ignores stale layout');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.products WHERE occasion=new_id),'No-plan sale retains products');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_fields f JOIN public.forms fm ON fm.id=f.form WHERE fm.occasion=new_id AND f.type='spot'),'No-plan form has no seat selector');
 -- Bindings to decoration are not sellable places. Definite rejection can be corrected.
 EXECUTE 'SET LOCAL ROLE authenticated';
 draft_id:=gen_random_uuid(); command:=gen_random_uuid();
 d:=public.create_occasion_setup_draft(draft_id,target);
 payload:=payload||jsonb_build_object('blueprintMode','new','link','invalid-plan-'||draft_id);
 payload:=jsonb_set(payload,'{blueprintLayoutDraft,layout,nodes,0,kind}','"shape"');
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command);
  RAISE EXCEPTION 'Decoration-only plan accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 payload:=payload||jsonb_build_object('blueprintMode','copy','blueprintLayoutDraft',source#>'{blueprints,0,blueprintLayoutDraft}');
 d:=public.save_occasion_setup_draft(draft_id,(d->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft_id,(d->>'revision')::bigint,command);
 new_id:=(response->'data'->>'occasionId')::bigint;
 EXECUTE 'RESET ROLE';
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.form_fields f JOIN public.forms fm ON fm.id=f.form WHERE fm.occasion=new_id AND f.type='spot' AND f.is_ticket_field AND NOT coalesce(f.is_hidden,false)),'Active plan normalizes public seat selector');
 EXECUTE 'SET LOCAL ROLE authenticated';
 response:=public.delete_occasion_client_sync_v1(new_id,gen_random_uuid());
 EXECUTE 'RESET ROLE';
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.occasions WHERE id=new_id),'A completed layout event can be deleted without binding FK failures');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id),'Deleting the copy preserves its source');
END $$;
