import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createInvitationHandler,
  type InvitationDependencies,
  type InvitationPreview,
} from "./handler.ts";

const draftId = "b4d54cd6-865a-448a-b9da-f260ea7e9631";
const request = () =>
  new Request("https://api.test/functions/v1/send-occasion-team-invitations", {
    method: "POST",
    headers: { Authorization: "Bearer fixture" },
    body: JSON.stringify({ draftId }),
  });
function fixture() {
  const preview: InvitationPreview = {
    canManage: true,
    sendConfirmed: true,
    recipients: [{
      email: "editor@example.org",
      kind: "account",
      role: "editor",
    }, { email: "viewer@example.org", kind: "new", role: "read_only" }],
    event: { id: 7, title: '<Event "title">', unit: 3, organization: 2 },
    organizationData: { DEFAULT_URL: "https://tenant.test", APP_NAME: "App" },
  };
  const inputs: unknown[] = [];
  const enqueues: Record<string, unknown>[] = [];
  const deps: InvitationDependencies = {
    preview: async () => preview,
    prepare: async (input) => {
      inputs.push(input);
      return { p_sealed: { ciphertext: "fixture" }, p_content_hash: "digest" };
    },
    enqueue: async (_, args) => {
      enqueues.push(args);
      return { message_id: "id", status: "queued" };
    },
    token: () => "a".repeat(64),
  };
  return { preview, inputs, enqueues, deps };
}
Deno.test("confirmation and finalized event guard preparation and all sends", async () => {
  const f = fixture();
  f.preview.sendConfirmed = false;
  assertEquals((await createInvitationHandler(f.deps)(request())).status, 409);
  assertEquals(f.inputs.length, 0);
  assertEquals(f.enqueues.length, 0);
  f.preview.sendConfirmed = true;
  f.preview.event.id = 0;
  assertEquals((await createInvitationHandler(f.deps)(request())).status, 409);
  assertEquals(f.inputs.length, 0);
});
Deno.test("safe invitation carries only link and requested role, never password", async () => {
  const f = fixture();
  const result = await createInvitationHandler(f.deps)(request());
  assertEquals(await result.json(), {
    complete: true,
    results: [{ email: "editor@example.org", status: "queued" }, {
      email: "viewer@example.org",
      status: "queued",
    }],
  });
  assertEquals(f.enqueues.map((x) => x.p_role), ["editor", "read_only"]);
  assert(f.enqueues.every((x) => x.p_token_hash !== "a".repeat(64)));
  assert(!JSON.stringify(f.inputs).includes("password"));
  const input = f.inputs[0] as { substitutions: Record<string, string> };
  assertEquals(
    input.substitutions.eventTitle,
    "&lt;Event &quot;title&quot;&gt;",
  );
  assert(
    input.substitutions.invitationUrl.startsWith(
      "https://tenant.test/team-invitation?token=",
    ),
  );
});
Deno.test("partial queue failure is explicit and existing access is skipped", async () => {
  const f = fixture();
  f.preview.recipients[0].alreadyEditor = true;
  f.deps.enqueue = async () => {
    throw new Error("queue unavailable");
  };
  const result = await createInvitationHandler(f.deps)(request());
  assertEquals(await result.json(), {
    complete: false,
    results: [{ email: "editor@example.org", status: "already_editor" }, {
      email: "viewer@example.org",
      status: "failed",
    }],
  });
  assertEquals(f.inputs.length, 1);
});
Deno.test("unauthorized and unsafe origin requests never prepare invitations", async () => {
  const f = fixture();
  f.preview.canManage = false;
  assertEquals((await createInvitationHandler(f.deps)(request())).status, 403);
  f.preview.canManage = true;
  f.preview.organizationData.DEFAULT_URL = "https://user:pass@tenant.test";
  assertEquals((await createInvitationHandler(f.deps)(request())).status, 422);
  assertEquals(f.inputs.length, 0);
});
