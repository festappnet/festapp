import {assertEquals,assertStringIncludes} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {bankSyncWarningEmail} from './bankSyncWarningEmail.ts';
Deno.test('bank warning is actionable and escapes account content',()=>{
 const email=bankSyncWarningEmail('admin@example.invalid',{account_title:'<script>bank</script>',warning_code:'stale',language:'cs'},'sender@example.invalid');
 assertEquals(email.to,'admin@example.invalid');
 assertStringIncludes(email.html,'&lt;script&gt;bank&lt;/script&gt;');
 assertStringIncludes(email.html,'30 minut');
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
