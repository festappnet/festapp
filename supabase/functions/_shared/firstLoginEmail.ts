import type { PreparedEmail } from "./emailDelivery.ts";

const escape = (value: unknown) => String(value ?? "").replace(/[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);

export function firstLoginEmail(recipient: string, data: Record<string, unknown>, sender: string): PreparedEmail {
  return {
    from: `Festapp <${sender}>`, to: recipient, replyTo: sender,
    subject: data.verification === true ? "Festapp - ověření upozornění na první přihlášení" : "Festapp - první přihlášení nového uživatele",
    html: `<h2>${data.verification === true ? "Test upozornění - nejde o skutečnou registraci" : "Nový uživatel se poprvé přihlásil"}</h2><p>Aplikace: ${escape(data.app_name)}</p><p>Jméno: ${escape(data.name)}</p><p>E-mail: ${escape(data.email)}</p><p>Přihlášení: ${escape(data.signed_in_at)}</p>`,
    attachments: [],
  };
}
