import type { PreparedEmail } from "./emailDelivery.ts";

const escape = (value: unknown) => String(value ?? "").replace(/[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);

export function unitVerificationEmail(recipient: string, data: Record<string, unknown>, sender: string): PreparedEmail {
  const url = new URL(String(data.review_url));
  if (url.protocol !== "https:" || url.username || url.password || !/^\/organizationEdit\/\d+$/.test(url.pathname) || url.search || url.hash) {
    throw new Error("invalid_verification_review_url");
  }
  return {
    from: `Festapp <${sender}>`, to: recipient, replyTo: sender,
    subject: "Žádost o ověření pořadatele",
    html: `<h2>Nová žádost o ověření pořadatele</h2><p>Platforma: ${escape(data.app_name)}</p><p>Právní název: ${escape(data.legal_name)}</p><p>IČO / registrační číslo: ${escape(data.registration_number)}</p><p><a href="${escape(url.href)}">Otevřít žádosti o ověření</a></p><p>Po přihlášení zkontrolujte údaje a oprávnění zástupce. Načtení z ARES samo o sobě neznamená ověření pořadatele.</p>`,
    attachments: [],
  };
}
