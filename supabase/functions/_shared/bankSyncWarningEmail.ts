import type { PreparedEmail } from './emailDelivery.ts';
const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]!);

export function bankSyncWarningEmail(recipient: string,data: Record<string,unknown>,sender: string): PreparedEmail {
  const czech = !['en','de','pl','uk'].includes(String(data.language).split(/[-_]/)[0]);
  const code = String(data.warning_code);
  const actionRequired = ['token_missing','token_invalid','account_mismatch','email_missing','connection_disabled'].includes(code);
  const reasons: Record<string,string> = czech ? {
    token_missing:'Není nastavený API token.',
    token_invalid:'Fio odmítlo API token jako neplatný nebo neaktivní. Ověřte jeho platnost a autorizaci v internetovém bankovnictví.',
    account_mismatch:'Účet vrácený bankou neodpovídá propojenému účtu. Zkontrolujte, ke kterému účtu API token patří.',
    connection_disabled:'Synchronizační služba hlásí vypnutý příjem nebo načítání výpisů, přestože má být synchronizace zapnutá.',
    email_missing:'Není nastavená adresa pro předávání bankovních oznámení.',
    temporary_failure:'Načítání výpisů z Fio naráží na dočasné chyby, omezení požadavků nebo timeouty. Příčinou může být banka i spojení k ní.',
    unavailable:'Nedaří se ověřit stav synchronizační služby BankSync. To samo o sobě neznamená výpadek banky ani neplatný token.',
    stale:'Delší dobu nebylo potvrzeno úspěšné načtení bankovního výpisu.',
    bank_error:'Stav bankovního napojení se nedaří spolehlivě ověřit.',
  } : {
    token_missing:'The API token is missing.',
    token_invalid:'Fio rejected the API token as invalid or inactive. Check its validity and authorization in online banking.',
    account_mismatch:'The account returned by the bank does not match the linked account. Check which account the API token belongs to.',
    connection_disabled:'The synchronization service reports disabled ingestion or statement fetching although synchronization should be enabled.',
    email_missing:'The bank notification forwarding address is missing.',
    temporary_failure:'Fetching Fio statements encounters temporary errors, rate limits or timeouts. The bank or the connection to it may be responsible.',
    unavailable:'The BankSync service status cannot be verified. This alone does not indicate a bank outage or an invalid token.',
    stale:'No successful bank statement fetch has been confirmed for an extended period.',
    bank_error:'The bank connection status cannot be verified reliably.',
  };
  const heading = czech
    ? actionRequired ? 'Bankovní napojení vyžaduje Váš zásah' : 'Načítání bankovních plateb má zpoždění'
    : actionRequired ? 'Bank connection requires your attention' : 'Bank payment synchronization is delayed';
  const guidance = czech
    ? actionRequired
      ? 'Problém trvá alespoň 10 minut. Otevřete nastavení účtu, záložku Propojení s bankou, a opravte uvedenou závadu.'
      : 'Potíže trvají alespoň hodinu. Automatické pokusy pokračují. Kvůli tomuto upozornění neměňte API token ani nevypínejte synchronizaci. Pokud potíže přetrvávají, kontaktujte podporu Festapp.'
    : actionRequired
      ? 'The problem has persisted for at least 10 minutes. Open the bank connection settings and correct the issue described above.'
      : 'The problem has persisted for at least one hour. Automatic retries continue. Do not replace the API token or disable synchronization because of this warning. Contact Festapp support if the problem persists.';
  const impact = czech
    ? 'Platby se mohou přiřazovat k objednávkám se zpožděním. Před připomenutím platby zákazníkovi ověřte výpis z účtu.'
    : 'Payments may be matched to orders with a delay. Check the bank statement before reminding a customer to pay.';
  const audience = czech
    ? 'Upozornění dostáváte jako správce tohoto bankovního účtu. Stejné upozornění posíláme jednou za incident na každou e-mailovou adresu.'
    : 'You receive this warning as an administrator of this bank account. We send this warning once per incident to each email address.';
  return {
    from:`Festapp <${sender}>`,to:recipient,replyTo:sender,
    subject:`Festapp - ${heading}`,
    html:`<h2>${heading}</h2><p>${czech?'Účet':'Account'}: <strong>${escape(data.account_title)}</strong></p><p>${czech?'Zaznamenaný stav':'Observed status'}: ${escape(reasons[code] ?? reasons.bank_error)}</p><p>${guidance}</p><p>${impact}</p><p>${audience}</p>`,
    attachments:[],
  };
}
