import { assertEquals, assertRejects, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executeMemberAccess, type AccessDependencies, type AccessPreview } from "./handler.ts";
import { renderEmail } from "../_shared/emailDelivery.ts";
function fixture(mode = "invite_to_accept") {
 let rendered = 0, staged = 0, committed = 0;
 const preview: AccessPreview = { actor: "actor", intentHash: "a".repeat(64), previewHash: "b".repeat(64),
  scope: { type: "unit", id: 1 }, unit: 1, occasion: null, organization: 3, email: "member@example.invalid", recipient: "member@example.invalid",
  title: "Organization & team", destination: "/unit/1/edit", roles: { is_editor: true }, communication: mode,
  organizationData: { DEFAULT_URL: "https://example.invalid", APP_NAME: "Festapp", DEFAULT_LANGUAGE: "en" } };
 const deps: AccessDependencies = {
  preview: () => Promise.resolve(preview),
  prepare: async input => {
   rendered++;
   const substitutions = input.substitutions as Record<string, string>;
   assert(!JSON.stringify(substitutions).includes("undefined"));
   return { p_sealed: { sealed: true }, p_content_hash: "c".repeat(64) };
  },
  stage: args => { staged++; assertEquals(args.p_actor, "actor"); assertEquals(args.p_intent_hash, preview.intentHash); return Promise.resolve("prepared"); },
  commit: () => { committed++; return Promise.resolve({ data: { communication: { messageId: "message", state: "queued" } } }); },
  token: () => "1".repeat(64),
 };
 return { deps, preview, counts: () => [rendered, staged, committed] };
}
Deno.test("receipt replay bypasses new token/render and preserves the committed message", async () => {
 const f = fixture(); f.preview.replay = { data: { communication: { messageId: "original" } } };
 assertEquals(await executeMemberAccess(f.deps, "Bearer fixture", "id", {}), f.preview.replay);
 assertEquals(f.counts(), [0, 0, 0]);
});
Deno.test("unit offer binds server context and renders inherited templates without an occasion", async () => {
 const f = fixture();
 f.deps.prepare = async input => {
  assertEquals(input.context, { unit: 1, organization: 3, occasion: null });
  const rendered = await renderEmail(input as Parameters<typeof renderEmail>[0], async () => ({ template: {
   id: 1, subject: "{{occasionTitle}} - {{roleLabel}}", html: '<a href="{{invitationUrl}}">{{occasionTitle}}</a>',
  } }));
  assert(rendered.html.includes("https://example.invalid/team-invitation?token="));
  assert(!rendered.html.includes("{{"));
  assert(rendered.html.includes("Organization &amp; team"));
  assert(!rendered.html.includes("&amp;amp;"));
  return { p_sealed: { fixture: true }, p_content_hash: "c".repeat(64) };
 };
 await executeMemberAccess(f.deps, "Bearer fixture", "id", {});
});
Deno.test("preparation failure never commits membership, password or receipt", async () => {
 const f = fixture("participant_credentials");
 f.deps.prepare = () => Promise.reject(new Error("email_preparation_deferred"));
 await assertRejects(() => executeMemberAccess(f.deps, "Bearer fixture", "id", {}));
 assertEquals(f.counts(), [0, 0, 0]);
});
Deno.test("participant producer prepares a generated six-digit password with SIGN_IN_CODE", async () => {
 const f = fixture("participant_credentials");
 let credential: unknown;
 f.deps.prepare = input => { assertEquals(input.templateCode, "SIGN_IN_CODE"); credential = (input.substitutions as Record<string, string>).code;
  assert(/^\d{6}$/.test(String(credential))); return Promise.resolve({ p_sealed: {}, p_content_hash: "a".repeat(64) }); };
 f.deps.stage = args => { assertEquals(args.p_password, credential); assertEquals(args.p_token_hash, null); return Promise.resolve("preparation"); };
 await executeMemberAccess(f.deps, "Bearer fixture", "id", {});
});
Deno.test("notification-only prepares no password or acceptance token", async () => {
 const f = fixture("notify_existing_access");
 f.deps.stage = args => { assertEquals(args.p_password, null); assertEquals(args.p_token_hash, null); return Promise.resolve("preparation"); };
 await executeMemberAccess(f.deps, "Bearer fixture", "id", {});
});

Deno.test("generated credential survives the actual inherited render and encrypted snapshot unchanged", async () => {
 const { sealEmail, openEmail } = await import("../_shared/emailPayload.ts");
 const before = Deno.env.get("EMAIL_PAYLOAD_KEY");
 Deno.env.set("EMAIL_PAYLOAD_KEY", btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))));
 try {
  const f = fixture("participant_credentials");
  f.deps.prepare = async input => {
   const rendered = await renderEmail(input as Parameters<typeof renderEmail>[0], async (_, context) => {
    assertEquals(context.unit, 1); assertEquals(context.occasion, null);
    return { template: { id: "unit-custom", subject: "{{appName}}", html: "<p>{{email}} {{code}}</p>" }, wrapper: { html: "<main>{{content}}</main>" } };
   });
   return { p_sealed: await sealEmail(rendered), p_content_hash: "a".repeat(64) };
  };
  f.deps.stage = async args => {
   const prepared = args.p_prepared as { p_sealed: Record<string,string> };
   const opened = await openEmail<{ html: string }>(prepared.p_sealed);
   assert(opened.html.includes(String(args.p_password)));
   assert(opened.html.includes("member@example.invalid"));
   assert(!opened.html.includes("{{"));
   return "preparation";
  };
  await executeMemberAccess(f.deps, "Bearer fixture", "id", {});
 } finally { if (before === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY"); else Deno.env.set("EMAIL_PAYLOAD_KEY", before); }
});
