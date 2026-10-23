// Produces reviewable provisioning SQL. Never connects or mutates a database.
import fs from 'node:fs';
const organization = process.argv[2];
if (!/^[1-9][0-9]*$/.test(organization || '')) throw new Error('Supply the verified organization ID');
const templates = JSON.parse(fs.readFileSync(new URL('./email/templates.en.json', import.meta.url)));
const literal = value => "'" + String(value).replaceAll("'", "''") + "'";
console.log(`BEGIN;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=${organization} AND data->>'DEFAULT_LANGUAGE'='en') THEN
  RAISE EXCEPTION 'Verified English organization required'; END IF;
END $$;`);
for (const row of templates) {
  console.log(`INSERT INTO public.email_templates(organization,code,title,subject,html)
SELECT ${organization},${literal(row.code)},${literal(row.title)},${literal(row.subject)},${literal(row.html)}
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates WHERE organization=${organization} AND unit IS NULL AND occasion IS NULL AND code=${literal(row.code)});`);
}
console.log(`INSERT INTO public.email_wrappers(organization,title,html)
SELECT ${organization},'English service wrapper','<html lang="en"><body>{{content}}</body></html>'
WHERE NOT EXISTS(SELECT 1 FROM public.email_wrappers WHERE organization=${organization} AND unit IS NULL AND occasion IS NULL);
COMMIT;`);
