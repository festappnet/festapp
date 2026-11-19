import type { PreparedEmail } from "./emailDelivery.ts";

const escape = (value: unknown) => String(value ?? "").replace(/[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);

function reviewUrl(data: Record<string, unknown>) {
  const url = new URL(String(data.review_url));
  if (url.protocol !== "https:" || url.username || url.password || !/^\/organizationEdit\/\d+$/.test(url.pathname) || url.search || url.hash) {
    throw new Error("invalid_measurement_review_url");
  }
  return url;
}

export function measurementApprovalEmail(recipient: string, data: Record<string, unknown>, sender: string): PreparedEmail {
  const url = reviewUrl(data);
  const en = data.lang === "en";
  const websites = Array.isArray(data.proposed_websites) ? data.proposed_websites : [];
  const sitesHtml = `<p>${en ? "Organizer websites (consent transfer is self-service)" : "Weby pořadatele (přenos souhlasu nastavuje pořadatel)"}</p><ul>${websites.map(site => `<li>${escape(site)}</li>`).join("")}</ul>`;
  return {
    from: `Festapp <${sender}>`, to: recipient, replyTo: sender,
    subject: en ? "Request to enable form measurement" : "Žádost o povolení měření formulářů",
    html: en
      ? `<h2>New request to enable form measurement</h2><p>Platform: ${escape(data.organization_title)}</p><p>Organizer: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p>${sitesHtml}<p><a href="${escape(url.href)}">Open organization administration</a></p><p>Please review the request and configure platform permission and the organizer's measurement runtime using the existing platform procedure.</p>`
      : `<h2>Nová žádost o povolení měření formulářů</h2><p>Platforma: ${escape(data.organization_title)}</p><p>Pořadatel: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p>${sitesHtml}<p><a href="${escape(url.href)}">Otevřít správu organizace</a></p><p>Po přihlášení posuďte žádost a nastavte povolení platformy a měřicí runtime pořadatele stávajícím postupem platformy.</p>`,
    attachments: [],
  };
}

// Same recipients and review link as the measurement request; only the
// platform decision differs (analytics.organization_policy.meta_capi_enabled).
export function metaCapiApprovalEmail(recipient: string, data: Record<string, unknown>, sender: string): PreparedEmail {
  const url = reviewUrl(data);
  const en = data.lang === "en";
  return {
    from: `Festapp <${sender}>`, to: recipient, replyTo: sender,
    subject: en ? "Request to enable Meta CAPI" : "Žádost o povolení Meta CAPI",
    html: en
      ? `<h2>New request to enable Meta Conversions API</h2><p>Platform: ${escape(data.organization_title)}</p><p>Organizer: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p><p><a href="${escape(url.href)}">Open organization administration</a></p><p>Please review the request and configure the platform's Meta CAPI permission using the existing platform procedure. An organization administrator then sets up the connection.</p>`
      : `<h2>Nová žádost o povolení Meta Conversions API</h2><p>Platforma: ${escape(data.organization_title)}</p><p>Pořadatel: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p><p><a href="${escape(url.href)}">Otevřít správu organizace</a></p><p>Po přihlášení posuďte žádost a nastavte povolení Meta CAPI stávajícím postupem platformy. Propojení pak nastaví správce organizace.</p>`,
    attachments: [],
  };
}
