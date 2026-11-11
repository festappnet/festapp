import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createInvitationHandler, type InvitationPreview } from "./handler.ts";
const draftId = "b4d54cd6-865a-448a-b9da-f260ea7e9631";
const req = () => new Request("https://example.invalid", { method: "POST", headers: { Authorization: "Bearer fixture" }, body: JSON.stringify({ draftId }) });
function fixture() {
 const preview: InvitationPreview = { canManage: true, sendConfirmed: true, event: { id: 4, unit: 2, organization: 3, title: "Team" }, organizationData: { DEFAULT_URL: "https://example.invalid" },
  recipients: [{ email: "a@example.invalid", kind: "new", role: "editor" }, { email: "b@example.invalid", kind: "account", role: "read_only" }] };
 const calls: Array<{ command: string; request: Record<string, unknown> }> = [];
 const handler = createInvitationHandler({ preview: () => Promise.resolve(preview), execute: (_, command, request) => { calls.push({ command, request }); return Promise.resolve({}); } });
 return { preview, calls, handler };
}
Deno.test("setup retry reuses each recipient command and preserves scoped role selection", async () => {
 const f = fixture(); await f.handler(req()); await f.handler(req());
 assertEquals(f.calls[0].command, f.calls[2].command); assertEquals(f.calls[1].command, f.calls[3].command);
 assertEquals(f.calls[1].request.roles, { is_editor: false, is_editor_view: true });
 assertEquals(f.calls[0].request.sourceDraft, draftId);
});
Deno.test("unconfirmed setup never executes invitations", async () => {
 const f = fixture(); f.preview.sendConfirmed = false;
 assertEquals((await f.handler(req())).status, 409); assertEquals(f.calls.length, 0);
});
Deno.test("already granted setup roles do not create duplicate offers", async () => {
 const f = fixture(); f.preview.recipients[0].alreadyEditor = true;
 await f.handler(req()); assertEquals(f.calls.length, 1);
});
Deno.test("one failed recipient does not roll back another recipient", async () => {
 const f = fixture();
 const handler = createInvitationHandler({ preview: () => Promise.resolve(f.preview), execute: (_, command, request) => request.email === "a@example.invalid" ? Promise.reject(new Error()) : Promise.resolve(command) });
 const result = await (await handler(req())).json(); assertEquals(result.complete, false);
 assertEquals(result.results.map((r: { status: string }) => r.status), ["failed", "queued"]);
});
