BEGIN;
DO $$
DECLARE oc bigint; h bigint; session jsonb; r jsonb; pg jsonb; sid uuid; token text; manifest jsonb;
BEGIN
 SELECT id INTO oc FROM public.occasions LIMIT 1;
 INSERT INTO public.occasions_hidden(secret) VALUES('SNAPSHOT_TEST_ONLY') RETURNING id INTO h;UPDATE public.occasions SET occasion_hidden=h WHERE id=oc;
 session:=public.open_scanner_session('SNAPSHOT_TEST_ONLY');sid:=(session#>>'{data,session_id}')::uuid;token:=session#>>'{data,token}';
 r:=public.prepare_scanner_snapshot(sid,token);PERFORM assert_eq(r->>'code','200','snapshot prepared');manifest:=r->'data';
 FOR pg IN SELECT value FROM jsonb_array_elements(manifest->'pages') LOOP
  r:=public.get_scanner_snapshot_page(sid,token,(manifest->>'snapshot_id')::uuid,(pg->>'index')::integer);
  PERFORM assert_eq(encode(digest(convert_to(r#>>'{data,payload_text}','UTF8'),'sha256'),'hex'),pg->>'digest','digest covers exact UTF8 payload');
 END LOOP;
 r:=public.prepare_scanner_snapshot(sid,token);PERFORM assert_eq(r->>'code','429','snapshot rebuild bounded');
 r:=public.get_scanner_snapshot_page(sid,token,gen_random_uuid(),0);PERFORM assert_eq(r->>'code','404','foreign snapshot is not readable');
END $$;
ROLLBACK;
