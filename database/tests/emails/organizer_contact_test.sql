BEGIN;
DO $$
DECLARE
 sender text := 'organizer-contact-' || gen_random_uuid() || '@example.invalid';
 submission uuid := gen_random_uuid();
 sealed jsonb := '{"v":"1","iv":"test","ciphertext":"test"}';
 digest text := repeat('a',64);
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=3) THEN
  INSERT INTO public.organizations(id,title) VALUES (3,'Organizer contact fixture');
 END IF;
 IF has_function_privilege('anon','public.enqueue_organizer_contact_v1(uuid,text,jsonb,text)','EXECUTE') OR
  has_function_privilege('authenticated','public.enqueue_organizer_contact_v1(uuid,text,jsonb,text)','EXECUTE') THEN
  RAISE EXCEPTION 'unprivileged caller can enqueue organizer contact';
 END IF;
 IF public.enqueue_organizer_contact_v1(submission,sender,sealed,digest)<>'accepted' OR
  public.enqueue_organizer_contact_v1(submission,sender,sealed,digest)<>'accepted' OR
  public.enqueue_organizer_contact_v1(submission,sender,sealed,repeat('b',64))<>'conflict' THEN
  RAISE EXCEPTION 'contact receipt does not distinguish retries and conflicts';
 END IF;
 IF (SELECT count(*) FROM public.email_messages
   WHERE organization=3 AND dedupe_key='organizer-contact:'||submission
   AND recipient='info@vstupenky.online' AND prepared=sealed AND tracking_policy='disabled')<>1 THEN
  RAISE EXCEPTION 'contact must create one sealed, untracked email to the organizers mailbox';
 END IF;
 FOR i IN 1..2 LOOP
  PERFORM public.enqueue_organizer_contact_v1(gen_random_uuid(),sender,sealed,digest);
 END LOOP;
 BEGIN
  PERFORM public.enqueue_organizer_contact_v1(gen_random_uuid(),sender,sealed,digest);
  RAISE EXCEPTION 'sender exceeded contact admission budget';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL;
 END;
 IF public.enqueue_organizer_contact_v1(submission,sender,sealed,digest)<>'accepted' THEN
  RAISE EXCEPTION 'known retries must precede admission';
 END IF;
END $$;
ROLLBACK;
