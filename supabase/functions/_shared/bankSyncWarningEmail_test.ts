import {assertEquals,assertStringIncludes} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {bankSyncWarningEmail} from './bankSyncWarningEmail.ts';
Deno.test('bank warning is actionable and escapes account content',()=>{
 const email=bankSyncWarningEmail('admin@example.invalid',{account_title:'<script>bank</script>',warning_code:'token_missing',language:'cs'},'sender@example.invalid');
 assertEquals(email.to,'admin@example.invalid');
 assertStringIncludes(email.html,'&lt;script&gt;bank&lt;/script&gt;');
 assertStringIncludes(email.html,'10 minut');
 assertStringIncludes(email.html,'Propojení s bankou');
 assertEquals(email.html.includes('<script>'),false);
 assertEquals(email.attachments.length,0);
});
Deno.test('bank warning supports English and safe unknown problem fallback',()=>{
 const email=bankSyncWarningEmail('admin@example.invalid',{account_title:'Bank',warning_code:'unexpected-private-bank-payload',language:'en'},'sender@example.invalid');
 assertStringIncludes(email.html,'once per incident');
 assertStringIncludes(email.html,'cannot be verified');
 assertEquals(email.html.includes('unexpected-private-bank-payload'),false);
});

for (const code of ['temporary_failure','unavailable','stale','bank_error']) {
 Deno.test(`availability warning ${code} explains retry without asking for token replacement`,()=>{
  const email=bankSyncWarningEmail('admin@example.invalid',{account_title:'Bank',warning_code:code,language:'cs'},'sender@example.invalid');
  assertStringIncludes(email.subject,'zpoždění');
  assertStringIncludes(email.html,'alespoň hodinu');
  assertStringIncludes(email.html,'Automatické pokusy pokračují');
  assertStringIncludes(email.html,'neměňte API token');
  assertEquals(email.html.includes('opravte uvedenou závadu'),false);
 });
}
for (const code of ['token_invalid','account_mismatch','email_missing','connection_disabled']) {
 Deno.test(`configuration warning ${code} requires administrator action`,()=>{
  const email=bankSyncWarningEmail('admin@example.invalid',{account_title:'Bank',warning_code:code,language:'cs'},'sender@example.invalid');
  assertStringIncludes(email.subject,'zásah');
  assertStringIncludes(email.html,'Propojení s bankou');
  assertEquals(email.html.includes('neměňte API token'),false);
 });
}
