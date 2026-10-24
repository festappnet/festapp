-- Synthetic organization config and real email templates for the optional local sink.
-- Never seeds the new organizer: registration must create the account and roles.
DO $$ BEGIN IF (SELECT title FROM public.organizations WHERE id=1)<>'Test Organization' THEN RAISE EXCEPTION 'Wrong disposable tenant'; END IF; END $$;
UPDATE public.organizations SET data=data||'{"APP_NAME":"Synthetic vstupenky.online","DEFAULT_URL":"https://localhost:59803","DEFAULT_LANGUAGE":"cs","PLATFORMS":[]}'::jsonb WHERE id=1;
INSERT INTO public.email_templates(organization,code,title,subject,html)
SELECT 1,code,title,subject,html FROM (VALUES
 ('SIGN_IN_CODE','Local signup capture','Přihlášení {{appName}}','<h1>Přihlašovací kód</h1><p>{{email}}</p><strong>{{code}}</strong>'),
 ('RESET_PASSWORD','Local reset capture','Obnova hesla {{appName}}','<a href="{{resetPasswordLink}}">Nastavit nové heslo</a>')) AS t(code,title,subject,html)
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates e WHERE e.organization=1 AND e.code=t.code);
-- Provider transport is the explicitly guarded local sink; no AWS credentials.
UPDATE public.email_capacity SET paused=false,account_id='local-sink',region='local',shared_account=false,max_rate=20,daily_quota=1000,provider_sent_24h=0,quota_at=now(),worker_url=NULL;
