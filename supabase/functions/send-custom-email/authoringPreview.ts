import { renderEmail } from "../_shared/emailDelivery.ts";
import { escapeEmailHtml } from "../_shared/emailActionLink.ts";
import examples from "../_shared/emailPreviewScenarios.json" with { type: "json" };

export interface AuthoringPreviewDependencies {
  senderAddress: string;
  read(authorization: string, input: any): Promise<any | null>;
}

/** The delivery renderer receives frozen synthetic facts, never customer data.
 * No queue/provider, capability, order lookup or bank lookup is reachable here. */
export async function authoringPreviewResponse(input: any, authorization: string,
    deps: AuthoringPreviewDependencies, headers: Record<string, string> = {}) {
  const reply = (body: unknown, status = 200) => Response.json(body, {
    status, headers: { ...headers, "Cache-Control": "no-store" },
  });
  if (!/^Bearer \S+$/i.test(authorization)) return reply({error: "Authentication required"}, 401);
  if (!input || Object.keys(input).some(k => !["action","entityType","entityId","organizationId","unitId","code","scenario","locale","tone"].includes(k)) ||
      !["unit","occasion"].includes(input.entityType) ||
      ![input.entityId,input.organizationId].every(v => Number.isSafeInteger(v) && v > 0) ||
      (input.unitId !== null && (!Number.isSafeInteger(input.unitId) || input.unitId < 1)) ||
      typeof input.code !== "string" || !/^[A-Za-z_][A-Za-z0-9_]{0,127}$/.test(input.code))
    return reply({error: "Invalid preview"}, 400);
  const sample = examples.records.find(r => r.templateCode === input.code && r.scenario === input.scenario &&
    r.locale === input.locale && r.tone === input.tone);
  if (!sample) return reply({error: "Unsupported preview scenario"}, 400);
  if (!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(deps.senderAddress))
    return reply({error: "Sender unavailable"}, 503);
  try {
    const resolved = await deps.read(authorization, input);
    if (!resolved?.template || !resolved.context) return reply({error: "Template access denied"}, 403);
    const rich = new Set<string>(sample.richCodes);
    const values = Object.fromEntries(Object.entries(sample.values).map(([k,v]) => [k, rich.has(k) ? v : escapeEmailHtml(String(v))]));
    const subjectValues = Object.fromEntries(Object.entries(sample.values).filter(([k]) => !rich.has(k)));
    const rendered = await renderEmail({
      to: "preview@example.invalid", from: deps.senderAddress, context: resolved.context,
      templateCode: input.code, substitutions: values, subjectSubstitutions: subjectValues,
      requiredLinks: sample.requiredLinks,
    }, async () => resolved);
    return reply({entityType:input.entityType, entityId:input.entityId, code:input.code,
      scenario:input.scenario, locale:input.locale, tone:input.tone,
      synthetic:true, senderAddress:rendered.from, subject:rendered.subject, html:rendered.html});
  } catch (_) { return reply({error: "Email preview unavailable"}, 503); }
}
