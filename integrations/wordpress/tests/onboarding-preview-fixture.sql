-- Restore only the public preview after rebuilding the disposable backend.
-- This is a synthetic copy, not evidence of a fresh organizer registration.
DO $$
DECLARE f bigint;
BEGIN
 IF current_database()<>'postgres'
    OR (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization'
    OR NOT EXISTS (SELECT 1 FROM public.forms WHERE link='embedded-synthetic') THEN
  RAISE EXCEPTION 'Disposable WordPress fixture required';
 END IF;
 IF EXISTS (SELECT 1 FROM public.forms WHERE link='36t9dry5') THEN RETURN; END IF;
 PERFORM set_config('request.jwt.claim.sub',(SELECT id::text FROM auth.users WHERE email='1+t@t.com'),true);
 f:=public.duplicate_form_to_occasion_internal_v1(
  (SELECT id FROM public.forms WHERE link='embedded-synthetic'),'embedded-event','cs');
 UPDATE public.forms SET
  link=public.reserve_public_link_internal('form',f,'36t9dry5',true),
  title='Můj první WordPress formulář',
  header='<h1>Můj první WordPress formulář</h1><p>Lokální testovací ukázka obnovená po restartu testovací databáze.</p>',
  participant_capacity=100
 WHERE id=f;
END $$;
