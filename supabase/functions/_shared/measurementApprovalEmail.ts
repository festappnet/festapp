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

export function metaCapiApprovalEmail(recipient: string, data: Record<string, unknown>, sender: string): PreparedEmail {
  const url = reviewUrl(data);
  const copy = data.lang === "en" ? {
    subject: "Request to enable Meta CAPI",
    heading: "New request to enable Meta Conversions API",
    platform: "Platform", organizer: "Organizer",
    review: "Open organization administration",
    handoff: "Send request to Festapp support",
    instructions: "A platform operator reviews the request. After approval, an organization administrator can set up the connection.",
  } : {
    subject: "Žádost o povolení Meta CAPI",
    heading: "Nová žádost o povolení Meta Conversions API",
    platform: "Platforma", organizer: "Pořadatel",
    review: "Otevřít správu organizace",
    handoff: "Předat žádost podpoře Festapp",
    instructions: "Žádost posoudí správce platformy. Po schválení může propojení nastavit správce organizace.",
  };
  const context = `${copy.platform}: ${url.href}\r\n${copy.organizer} (ID): ${String(data.unit_id ?? "")}`;
  const handoffUrl = `mailto:info@festapp.net?subject=${encodeURIComponent(copy.subject)}&body=${encodeURIComponent(context)}`;
  return {
    from: `Festapp <${sender}>`, to: recipient, replyTo: sender,
    subject: copy.subject,
    html: `<h2>${copy.heading}</h2><p>${copy.platform}: ${escape(data.organization_title)}</p><p>${copy.organizer}: ${escape(data.unit_title)} (ID: ${escape(data.unit_id)})</p><p>${copy.instructions}</p><p><a href="${escape(handoffUrl)}">${copy.handoff}</a></p><p><a href="${escape(url.href)}">${copy.review}</a></p>`,
    attachments: [],
  };
}
