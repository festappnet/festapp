import { generateFullOrder } from "../_shared/orderOverview.ts";
import {
  confirmationPaymentSubstitutions,
  paidPaymentSubstitutions,
} from "../_shared/orderEmailPresentation.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";
import { escapeEmailHtml } from "../_shared/emailActionLink.ts";

/** Read-only production rendering. Intentionally no queue, checkout, invoice,
 * payment-reference allocation, attachment generation or customer lookup. */
export interface SetupPreviewDependencies {
  draft(authorization: string, id: string, bytes: number): Promise<any | null>;
  catalog(authorization: string, unit: number): Promise<any | null>;
  sourceTemplates(authorization: string, occasion: number): Promise<any | null>;
  bank(
    authorization: string,
    draftId: string,
    accountId: number,
  ): Promise<string | null>;
  resolve: (code: string, context: any) => Promise<any>;
  senderAddress: string;
}
export async function setupPreviewResponse(
  input: any,
  authorization: string,
  deps: SetupPreviewDependencies,
  headers: Record<string, string> = {},
) {
  const reply = (body: unknown, status = 200) =>
    Response.json(body, {
      status,
      headers: { ...headers, "Cache-Control": "no-store" },
    });
  if (!/^Bearer \S+$/i.test(authorization)) {
    return reply({ error: "Authentication required" }, 401);
  }
  const bytes = new TextEncoder().encode(JSON.stringify(input)).length;
  if (bytes > 40000) return reply({ error: "Preview too large" }, 413);
  if (
    typeof input.draftId !== "string" ||
    !/^[0-9a-f-]{36}$/i.test(input.draftId) || !Array.isArray(input.tickets) ||
    input.tickets.length > 100 ||
    input.tickets.some((t: any) =>
      !t || !Array.isArray(t.products) || t.products.length > 100 ||
      t.products.some((id: any) => !Number.isSafeInteger(id))
    )
  ) return reply({ error: "Invalid preview" }, 400);
  const row = await deps.draft(authorization, input.draftId, bytes);
  if (!row || row.data?.finalizedOccasion) {
    return reply({ error: "Draft access denied" }, 403);
  }
  const d = row.data;
  const scope = await deps.catalog(authorization, row.unit);
  if (!scope?.unit || !scope.organization) {
    return reply({ error: "Email scope unavailable" }, 403);
  }
  const context = { unit: row.unit, organization: scope.organization.id };
  const products = new Map();
  for (const field of d.formDraft?.fields ?? []) {
    if (!field.is_hidden) {
      for (const p of field.product_type_data?.products ?? []) {
        if (!p.is_hidden) {
          products.set(p.id, {
            ...p,
            type_title: field.product_type_data.title,
          });
        }
      }
    }
  }
  const tickets = [];
  let total = 0;
  let currency: string | undefined;
  for (const [index, selected] of input.tickets.entries()) {
    const items = [];
    if (
      selected.seat &&
      ["group", "title"].some((k) =>
        typeof selected.seat[k] !== "string" || selected.seat[k].length > 500
      )
    ) return reply({ error: "Invalid seat label" }, 400);
    for (const id of selected.products) {
      const p = products.get(id);
      if (!p || !Number.isFinite(p.price) || p.price < 0) {
        return reply({ error: "Product unavailable" }, 400);
      }
      if (currency && currency !== p.currency_code) {
        return reply({ error: "Mixed currencies" }, 400);
      }
      currency = p.currency_code;
      total += p.price;
      items.push({
        ...p,
        title: escapeEmailHtml(p.title ?? ""),
        type_title: escapeEmailHtml(p.type_title ?? ""),
        ...(selected.seat
          ? {
            spot_group_title: escapeEmailHtml(selected.seat.group),
            spot_title: escapeEmailHtml(selected.seat.title),
          }
          : {}),
      });
    }
    tickets.push({ ticket_symbol: `PREVIEW-${index + 1}`, products: items });
  }
  const lang = input.locale === "en" ? "en" : "cs"; // same fallback as production emails
  const tone = ["formal", "informal"].includes(d.communicationTone)
    ? d.communicationTone
    : (scope.unit.data?.communication_tone === "informal"
      ? "informal"
      : "formal");
  const features = [{
    code: "ticket",
    is_enabled: (d.formDraft?.fields ?? []).some((f: any) =>
      f.type === "ticket" && !f.is_hidden
    ),
  }];
  const fields: Record<string, string> = {};
  for (const key of ["name", "surname", "email", "phone", "note"]) {
    if (
      input.fields?.[key] !== undefined &&
      (typeof input.fields[key] !== "string" || input.fields[key].length > 500)
    ) return reply({ error: "Invalid customer field" }, 400);
    fields[key] = escapeEmailHtml(input.fields?.[key] ?? "");
  }
  const bank = d.bankAccountId
    ? await deps.bank(authorization, input.draftId, d.bankAccountId)
    : null;
  const deadline = new Date(
    Date.now() + Math.max(0, Number(d.deadline) || 0) * 86400000,
  ).toISOString();
  const confirmation = confirmationPaymentSubstitutions(
    {
      amount: total,
      currency_code: currency ?? "CZK",
      account_number: "",
      account_number_human_readable: bank ?? "",
      deadline,
      variable_symbol: "PREVIEW",
    },
    features,
    lang,
    tone,
  );
  const overrides = new Map();
  if (d.copyEmails === true && Number.isSafeInteger(d.sourceId)) {
    const source = await deps.sourceTemplates(authorization, d.sourceId);
    if (!source) return reply({ error: "Copy source denied" }, 403);
    for (const t of source.templates ?? []) {
      if (t.occasion === d.sourceId) overrides.set(t.code, t);
    }
  }
  if (!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(deps.senderAddress)) {
    return reply({ error: "Sender unavailable" }, 503);
  }
  const messages = [];
  for (
    const code of [
      "TICKET_ORDER_CONFIRMATION",
      ...(total > 0 ? ["TICKET_ORDER_PAYMENT_DONE"] : []),
    ]
  ) {
    const substitutions = {
      ...fields,
      occasionTitle: escapeEmailHtml(d.title ?? ""),
      occasion_title: escapeEmailHtml(d.title ?? ""),
      orderSymbol: "PREVIEW",
      variableSymbol: "PREVIEW",
      accountNumber: bank ?? "",
      iban: "",
      deadline,
      fullOrder: generateFullOrder(fields, tickets, features, lang, "PREVIEW"),
      ...(code === "TICKET_ORDER_CONFIRMATION"
        ? confirmation
        : paidPaymentSubstitutions(
          total,
          total,
          currency ?? "CZK",
          features,
          lang,
          tone,
        )),
    };
    const prepared = await renderEmail({
      to: "preview@example.invalid",
      from: deps.senderAddress,
      context,
      templateCode: code,
      substitutions,
    }, async (templateCode, ctx) => {
      const resolved = await deps.resolve(templateCode, ctx);
      return {
        ...resolved,
        template: overrides.get(templateCode) ?? resolved?.template,
      };
    });
    messages.push({
      subject: prepared.subject,
      html: prepared.html,
      senderAddress: prepared.from,
    });
  }
  return reply({ messages, total, currency: currency ?? "CZK", locale: lang });
}
