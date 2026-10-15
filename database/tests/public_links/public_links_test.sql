BEGIN;
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; a bigint; b bigint; f bigint; first_link text;
 foreign_org bigint; old_revision bigint;
 command uuid:=gen_random_uuid(); response jsonb; copied bigint; draft uuid:=gen_random_uuid(); data jsonb;
BEGIN
 PERFORM create_user_for_test('public_links_manager','public_links_manager@test.local');
 actor:=get_user_id('public_links_manager');
 INSERT INTO public.organizations(title) VALUES('Public links test') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Links',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(unit_id,actor,true,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 response:=public.create_occasion_client_sync_v1(command,jsonb_build_object('unit',unit_id,'organization',org,'title','Ples','link','',
   'start_time',now(),'end_time',now()+interval '1 day'));
 a:=(response#>>'{data,occasionId}')::bigint;
 first_link:=response#>>'{data,occasion,link}';
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view) VALUES(a,actor,true,true,true,true,true);
 PERFORM assert_true(first_link ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$','short occasion code');
 PERFORM assert_eq(public.create_occasion_client_sync_v1(command,jsonb_build_object('unit',unit_id,'organization',org,'title','Ples','link','',
   'start_time',now(),'end_time',now()+interval '1 day'))#>>'{data,occasion,link}',first_link,'create replay keeps code');
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',a,'first-name') WHERE id=a;
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',a,'last-name') WHERE id=a;
 PERFORM assert_eq(public.get_occasion_by_link(first_link)->>'link','last-name','old random alias resolves directly');
 PERFORM assert_eq(public.get_occasion_for_edit_v1('first-name')->>'id',a::text,'admin alias same identity');
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',a,first_link) WHERE id=a;
 response:=public.create_occasion_client_sync_v1(gen_random_uuid(),jsonb_build_object('unit',unit_id,'organization',org,'title','Other','start_time',now(),'end_time',now()+interval '1 day'));
 b:=(response#>>'{data,occasionId}')::bigint;
 BEGIN
  PERFORM public.reserve_public_link_internal('occasion',b,'first-name');
  RAISE EXCEPTION 'Alias stolen';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM public.reserve_public_link_internal('occasion',a,''); RAISE EXCEPTION 'Empty update allowed';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.reserve_public_link_internal('occasion',a,'admin'); RAISE EXCEPTION 'Reserved path allowed';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 response:=public.create_form_client_sync_v1(first_link,'','Registration',gen_random_uuid());
 f:=(response#>>'{data,form,id}')::bigint;
 PERFORM assert_true((response#>>'{data,form,link}') ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$','short form code');
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',f,'form-old') WHERE id=f;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',f,'form-current') WHERE id=f;
 PERFORM assert_eq(public.resolve_form_link_internal('form-old'),f,'form alias identity');
 PERFORM assert_eq(public.get_form_fields('form-old')->>'code','200','legacy fields reader resolves alias using canonical product schema');
 PERFORM assert_eq(public.get_form_from_link('form-old')::jsonb#>>'{data,id}',f::text,'legacy public form delegates to canonical bundle');
 PERFORM assert_eq(public.get_form_for_edit('form-old')#>>'{data,form,link}','form-current','form edit alias canonical');
 INSERT INTO public.organizations(title) VALUES('Other public link tenant') RETURNING id INTO foreign_org;
 PERFORM assert_eq(public.get_app_config_v218(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',foreign_org,'link','first-name'))->>'code','404','occasion alias does not cross tenant');
 PERFORM assert_eq(public.get_app_config_v218(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',foreign_org,'form_link','form-old'))->>'code','404','form alias does not fall into another tenant context');
 copied:=public.duplicate_form(f);
 PERFORM assert_eq((SELECT link ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$' FROM public.forms WHERE id=copied),true,'legacy form duplicate uses allocator');
 copied:=public.copy_form_with_fields(f);
 PERFORM assert_eq((SELECT link ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$' FROM public.forms WHERE id=copied),true,'legacy form copy uses allocator');

 response:=public.update_occasion(jsonb_build_object('unit',unit_id,'organization',org,'title','Legacy create','link','',
  'start_time',now(),'end_time',now()+interval '1 day'));
 PERFORM assert_true((response#>>'{occasion,link}') ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$','legacy save returns server canonical code');
 response:=public.update_occasion(jsonb_build_object('id',response#>'{occasion,id}','unit',unit_id,'organization',org,'title','Legacy rename','link','legacy-renamed'));
 PERFORM assert_eq(response#>>'{occasion,link}','legacy-renamed','legacy rename returns canonical model');
 copied:=public.duplicate_occasion(a);
 PERFORM assert_eq((SELECT title FROM public.occasions WHERE id=copied),'Ples (copy)','legacy duplicate defaults to English');
 command:=gen_random_uuid();
 response:=public.duplicate_occasion_client_sync_v1(a,command,unit_id,'cs');
 copied:=(response#>>'{data,occasionId}')::bigint;
 PERFORM assert_eq((SELECT title FROM public.occasions WHERE id=copied),'Ples (kopie)','Czech stored title');
 PERFORM assert_eq((SELECT safe_label FROM public.client_commit_items WHERE entity_id=copied::text AND entity_type='occasion' ORDER BY commit_id DESC LIMIT 1),'Ples (kopie)','audit matches title');
 PERFORM assert_eq((SELECT count(*) FROM public.forms WHERE occasion=copied),(SELECT count(*) FROM public.forms WHERE occasion=a),'all forms copied');
 PERFORM assert_true((SELECT bool_and(link ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$') FROM public.forms WHERE occasion=copied),'every copied form receives its own short code');
 PERFORM assert_eq(public.duplicate_occasion_client_sync_v1(a,command,unit_id,'cs')#>>'{data,occasionId}',copied::text,'copy replay');
 response:=public.duplicate_occasion_client_sync_v1(copied,gen_random_uuid(),unit_id,'en');
 PERFORM assert_eq((SELECT title FROM public.occasions WHERE id=(response#>>'{data,occasionId}')::bigint),'Ples (copy)','copy of copy single translated suffix');
 PERFORM assert_eq(public.copy_occasion_title_internal('Name (Copy) (kopie)','xx'),'Name (copy)','unknown locale fallback strips suffixes');
 PERFORM assert_eq(length(public.copy_occasion_title_internal(repeat('a',500),'cs')),500,'suffix retained at title limit');
 PERFORM assert_eq(right(public.copy_occasion_title_internal(repeat('a',500),'cs'),8),' (kopie)','complete suffix');
 -- Exception rolls back reservation and the column together.
 BEGIN
  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',a,'rolled-back') WHERE id=a;
  RAISE EXCEPTION 'abort';
 EXCEPTION WHEN raise_exception THEN NULL; END;
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE slug='rolled-back'),'rollback leaves no reservation');
 PERFORM public.delete_occasion_client_sync_v1(b,gen_random_uuid());
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE occasion IS NULL),'delete leaves tombstone');
 PERFORM assert_true(NOT has_table_privilege('authenticated','public.forms','UPDATE'),'direct form link bypass denied');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.reserve_public_link_internal(text,bigint,text,boolean)','EXECUTE'),'allocator private');
 -- Existing draft save path owns localized prefill; finalization reuses immutable data.
 response:=public.create_occasion_setup_draft(draft,unit_id);
 data:=(response->'data') || jsonb_build_object('sourceId',a,'copy_locale','cs','copy_title_edited',false);
 response:=public.save_occasion_setup_draft(draft,(response->>'revision')::bigint,data,0);
 PERFORM assert_eq(response#>>'{data,title}','Ples (kopie)','draft SQL prefill');
 PERFORM assert_eq(public.save_occasion_setup_draft(draft,(response->>'revision')::bigint-1,data,0)#>>'{data,title}','Ples (kopie)','lost draft prefill response retries identically');

 data:=(response->'data') || jsonb_build_object('start',now(),'end',now()+interval '1 day','reviewConfirmed',true,'formEnabled',true);
 response:=public.save_occasion_setup_draft(draft,(response->>'revision')::bigint,data,5);
 command:=gen_random_uuid();
 data:=response;
 response:=public.finalize_occasion_setup_draft(draft,(response->>'revision')::bigint,command);
 PERFORM assert_eq(public.finalize_occasion_setup_draft(draft,(data->>'revision')::bigint,command)#>>'{data,occasionId}',response#>>'{data,occasionId}','wizard retry returns same event');
 PERFORM assert_eq(public.finalize_occasion_setup_draft(draft,(data->>'revision')::bigint+1,gen_random_uuid())#>>'{data,occasionId}',response#>>'{data,occasionId}','reopened completed wizard cannot duplicate event');
 PERFORM assert_true((response#>>'{data,link}') ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{8}$','wizard short code');
 -- Copied wizard configuration creates fresh field/product/seat IDs and can
 -- preserve an explicit edited title without forcing another copy suffix.
 draft:=gen_random_uuid();
 response:=public.create_occasion_setup_draft(draft,unit_id);
 SELECT x INTO data FROM jsonb_array_elements(public.get_occasion_setup_sources(unit_id)) x WHERE (x#>>'{occasion,id}')::bigint=a;
 data:=data#>'{forms,0}';
 data:=jsonb_set(data,'{link}','""'::jsonb);
 response:=public.save_occasion_setup_draft(draft,(response->>'revision')::bigint,(response->'data') || jsonb_build_object(
  'sourceId',a,'copy_locale','en','copy_title_edited',true,'title','My custom title',
  'formDraft',data,'formEnabled',true,'start',now(),'end',now()+interval '1 day','reviewConfirmed',true,
  'blueprintObjects',jsonb_build_array(jsonb_build_object('type','spot','x',1,'y',1,'product',data#>'{fields,2,product_type_data,products,0,id}')),
  'blueprintGroups','[]'::jsonb),5);
 response:=public.finalize_occasion_setup_draft(draft,(response->>'revision')::bigint,gen_random_uuid());
 copied:=(response#>>'{data,occasionId}')::bigint;
 PERFORM assert_eq((SELECT title FROM public.occasions WHERE id=copied),'My custom title','wizard honors manually edited copy title');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.form_fields ff JOIN public.forms fm ON fm.id=ff.form WHERE fm.occasion=copied AND ff.type='product_type'),'wizard materializes product fields');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.products p ON p.id=s.product WHERE s.occasion=copied AND p.occasion=copied),'wizard seats use newly owned products');
END $$;
-- Controlled source override is transaction local and never exposed as an RPC.
CREATE OR REPLACE FUNCTION public.random_public_link_internal() RETURNS text LANGUAGE sql SET search_path=public,extensions AS $$ SELECT '22222222'::text $$;
DO $$ DECLARE a bigint; b bigint; BEGIN
 SELECT id INTO a FROM public.occasions ORDER BY id LIMIT 1;
 INSERT INTO public.occasions(title,link,start_time,end_time) VALUES('Retry target','',now(),now()+interval '1 day') RETURNING id INTO b;
 INSERT INTO public.occasion_link_reservations(slug,occasion) VALUES('22222222',a);
 BEGIN
  PERFORM public.reserve_public_link_internal('occasion',b,NULL,true); RAISE EXCEPTION 'retry limit ignored';
 EXCEPTION WHEN unique_violation THEN
  PERFORM assert_eq(SQLERRM,'Public link allocation exhausted','bounded collision retry'); END;
END $$;
ROLLBACK;
