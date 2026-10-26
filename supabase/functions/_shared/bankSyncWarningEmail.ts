import type { PreparedEmail } from './emailDelivery.ts';
const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]!);

export function bankSyncWarningEmail(recipient: string,data: Record<string,unknown>,sender: string): PreparedEmail {
  const czech = !['en','de','pl','uk'].includes(String(data.language).split(/[-_]/)[0]);
  const reasons: Record<string,string> = czech ? {
    token_missing:'Není nastavený API token.',email_missing:'Není nastavená adresa pro předávání bankovních oznámení.',
    stale:'Déle než 30 minut se nepodařilo úspěšně načíst bankovní výpis.',
    bank_error:'Bankovní napojení hlásí chybu nebo se nedaří ověřit jeho stav.',
  } : {
    token_missing:'The API token is missing.',email_missing:'The bank notification forwarding address is missing.',
    stale:'No bank statement has been fetched successfully for over 30 minutes.',
    bank_error:'The bank connection reports an error or its status cannot be verified.',
  };
  const title=escape(data.account_title);
  return {
    from:`Festapp <${sender}>`,to:recipient,replyTo:sender,
    subject:czech?'Festapp - nefunguje automatická synchronizace bankovního účtu':'Festapp - automatic bank synchronization needs attention',
    html:czech
      ? `<h2>Nefunguje automatická synchronizace</h2><p>Účet: <strong>${title}</strong></p><p>${escape(reasons[String(data.warning_code)] ?? reasons.bank_error)}</p><p>Synchronizace je zapnutá, ale problém trvá alespoň 10 minut. Platby se nemusí automaticky přiřazovat k objednávkám.</p><p>Jste administrátorem tohoto účtu. Otevřete nastavení účtu, záložku Propojení s bankou, a zkontrolujte stav napojení, token nebo předávání bankovních oznámení. Případně kontaktujte ostatní administrátory účtu.</p><p>Dokud tato porucha trvá, stejné upozornění znovu neposíláme.</p>`
      : `<h2>Automatic bank synchronization needs attention</h2><p>Account: <strong>${title}</strong></p><p>${escape(reasons[String(data.warning_code)] ?? reasons.bank_error)}</p><p>Synchronization is enabled but this problem has persisted for at least 10 minutes. Payments may not be matched to orders automatically.</p><p>You are an administrator of this account. Open its bank connection settings and check the connection, API token or forwarded bank notifications. Contact another account administrator if needed.</p><p>We send this warning once per incident.</p>`,
    attachments:[],
  };
}
