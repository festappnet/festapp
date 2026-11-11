import type { PreparedEmail } from "./emailDelivery.ts";

const escape = (value: unknown) => String(value ?? "").replace(/[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);

export function measurementApprovalEmail(recipient: string, data: Record<string, unknown>, sender: string): PreparedEmail {
  const url = new URL(String(data.review_url));
  if (url.protocol !== "https:" || url.username || url.password || !/^\/organizationEdit\/\d+$/.test(url.pathname) || url.search || url.hash) {
    throw new Error("invalid_measurement_review_url");
  }
  const en = data.lang === "en";
  const websites = Array.isArray(data.proposed_websites) ? data.proposed_websites : [];
  const sitesHtml = `<p>${en ? "Proposed websites (require platform approval)" : "Navržené weby (vyžadují schválení platformou)"}</p><ul>${websites.map(site => `<li>${escape(site)}</li>`).join("")}</ul>`;
  return {
    from: `Festapp <${sender}>`, to: recipient, replyTo: sender,
    subject: en ? "Request to enable form measurement" : "Žádost o povolení měření formulářů",
    html: en
      ? `<h2>New request to enable form measurement</h2><p>Platform: ${escape(data.organization_title)}</p><p>Organizer: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p>${sitesHtml}<p><a href="${escape(url.href)}">Open organization administration</a></p><p>Please review the request and configure platform permission and the organizer's measurement runtime using the existing platform procedure.</p>`
      : `<h2>Nová žádost o povolení měření formulářů</h2><p>Platforma: ${escape(data.organization_title)}</p><p>Pořadatel: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p>${sitesHtml}<p><a href="${escape(url.href)}">Otevřít správu organizace</a></p><p>Po přihlášení posuďte žádost a nastavte povolení platformy a měřicí runtime pořadatele stávajícím postupem platformy.</p>`,
    attachments: [],
  };
}
