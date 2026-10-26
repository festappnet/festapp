BEGIN;
DO $$
DECLARE fixture jsonb; oc bigint; h bigint; session jsonb; r jsonb; pg jsonb; sid uuid; token text; manifest jsonb;
BEGIN
 fixture:=public.scanner_test_fixture(2);oc:=(fixture->>'occasion')::bigint;
 session:=public.open_scanner_session(fixture->>'scan_code');sid:=(session#>>'{data,session_id}')::uuid;token:=session#>>'{data,token}';
 r:=public.prepare_scanner_snapshot(sid,token);PERFORM assert_eq(r->>'code','200','snapshot prepared');manifest:=r->'data';
 FOR pg IN SELECT value FROM jsonb_array_elements(manifest->'pages') LOOP
  r:=public.get_scanner_snapshot_page(sid,token,(manifest->>'snapshot_id')::uuid,(pg->>'index')::integer);
  PERFORM assert_eq(encode(digest(convert_to(r#>>'{data,payload_text}','UTF8'),'sha256'),'hex'),pg->>'digest','digest covers exact UTF8 payload');
 END LOOP;
 r:=public.prepare_scanner_snapshot(sid,token);PERFORM assert_eq(r->>'code','429','snapshot rebuild bounded');
 r:=public.get_scanner_snapshot_page(sid,token,gen_random_uuid(),0);PERFORM assert_eq(r->>'code','404','foreign snapshot is not readable');
END $$;
ROLLBACK;
