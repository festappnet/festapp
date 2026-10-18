import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  deleteOneSignalUser,
  maskEmail,
  sha256,
} from "./accountDeletion.ts";

Deno.test("account deletion helpers hide identity and hash tokens", async () => {
  assertEquals(maskEmail("alice@example.test"), "a***@example.test");
  assertEquals((await sha256("opaque-token")).length, 64);
});

Deno.test("OneSignal deletion retries transient errors and treats 404 as absent", async () => {
  const statuses = [429, 503, 404];
  const waits: number[] = [];
  await deleteOneSignalUser("app", "secret", "user", {
    fetch: async (_url, init) => {
      assertEquals(init?.method, "DELETE");
      assertEquals((init?.headers as Record<string, string>).Authorization, "Key secret");
      return new Response("", { status: statuses.shift()! });
    },
    wait: async (milliseconds) => { waits.push(milliseconds); },
  });
  assertEquals(waits, [250, 500]);
});

Deno.test("OneSignal deletion does not retry permanent failures", async () => {
  await assertRejects(() => deleteOneSignalUser("app", "secret", "user", {
    fetch: async () => new Response("", { status: 401 }),
    wait: async () => { throw new Error("must not wait"); },
  }), Error, "onesignal_permanent");
});
