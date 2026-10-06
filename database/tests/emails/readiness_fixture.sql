-- Disposable rehearsal only. Production already has generic auth templates;
-- its schema-only test baseline needs these rows to represent that contract.
INSERT INTO public.email_templates(html,subject,code,title)
SELECT fixture.html,fixture.subject,fixture.code,fixture.code
FROM (VALUES
  ('<p>{{resetPasswordLink}}</p>','Reset {{appName}}','RESET_PASSWORD'),
  ('<p>{{code}}</p>','Sign in {{appName}}','SIGN_IN_CODE')
) fixture(html,subject,code)
WHERE NOT EXISTS (SELECT 1 FROM public.email_templates t
  WHERE t.code=fixture.code AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);
