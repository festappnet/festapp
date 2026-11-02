import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
Deno.env.set("SUPABASE_URL", "http://127.0.0.1:55499");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service-key");
Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon-key");
Deno.env.set("BANKSYNC_API_URL", "https://banksync.invalid");
Deno.env.set("BANKSYNC_TENANT_ADMIN_KEY", "synthetic-scoped-key");
let handle: (request: Request) => Promise<Response>;
const serve = Deno.serve;
Object.defineProperty(Deno, "serve", {
  value: (handler: typeof handle) => {
    handle = handler;
  },
  configurable: true,
});
let fetchHandler: typeof fetch;
globalThis.fetch =
  ((...args: Parameters<typeof fetch>) =>
    fetchHandler(...args)) as typeof fetch;
try {
  await import("../bank-sync-manage/index.ts");
} finally {
  Object.defineProperty(Deno, "serve", { value: serve, configurable: true });
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

for (const delayedReadback of [false, true]) {
  for (const lateFailure of [true, false]) {
    Deno.test(`status route discards late ${lateFailure ? "failure" : "success"} response including its diagnostics (delayed readback=${delayedReadback})`, async () => {
      let issued = 0, applied = 0, remoteCalls = 0, reads = 0;
      let state: Record<string, unknown> = {
        id: 1,
        remote_bank_account_id: "9",
        state: "connected",
        mode: "api",
        last_error: null,
        warning_pending: false,
      };
      const starts = [deferred<void>(), deferred<void>()];
      const responses = [deferred<Response>(), deferred<Response>()];
      const events: string[] = [];
      const readbackStarted = deferred<void>();
      const releaseReadback = deferred<void>();
      fetchHandler =
        (async (input: string | URL | Request, init?: RequestInit) => {
          const url = new URL(
            input instanceof Request ? input.url : String(input),
          );
          if (url.hostname === "banksync.invalid") {
            const i = remoteCalls++;
            events.push(`remote-${i + 1}`);
            starts[i].resolve();
            return responses[i].promise;
          }
          const body = init?.body ? JSON.parse(String(init.body)) : {};
          const name = url.pathname.split("/").pop()!;
          if (name === "user") return Response.json({ id: "fixture-user" });
          if (name === "get_bank_sync_connection") {
            if (delayedReadback && ++reads === 2) {
              readbackStarted.resolve();
              await releaseReadback.promise;
            }
            return Response.json({ ...state });
          }
          if (name === "begin_bank_sync_observation") {
            events.push(`begin-${++issued}`);
            return Response.json(String(issued));
          }
          if (name === "record_bank_sync_pull") {
            const token = Number(body.p_observation_id);
            if (token <= applied) return Response.json(false);
            applied = token;
            state = {
              ...state,
              observation_id: String(token),
              last_error: body.p_error,
              state: body.p_error ? "degraded" : "connected",
              warning_pending: body.p_error !== null,
            };
            return Response.json(true);
          }
          throw new Error(`Unexpected request: ${name}`);
        }) as typeof fetch;
      const request = () =>
        handle(
          new Request("http://127.0.0.1/bank-sync-manage", {
            method: "POST",
            headers: {
              authorization: "Bearer fixture-user-token",
              "content-type": "application/json",
            },
            body: JSON.stringify({ operation: "status", account_id: 42 }),
          }),
        );
      const bankResponse = (failure: boolean, prefix: string) =>
        Response.json({
          api_last_success_at: "2026-11-02T12:00:00Z",
          api_last_error: failure ? "fio_token_invalid_or_inactive" : null,
          api_token_prefix: prefix,
          api_last_failure: failure
            ? {
              version: 1,
              code: "FioTokenInvalidOrInactive",
              stage: "bank_http",
            }
            : null,
        });
      const old = request();
      await starts[0].promise;
      if (delayedReadback) {
        responses[0].resolve(bankResponse(lateFailure, "obsolete"));
        await readbackStarted.promise;
      }
      const recent = request();
      await starts[1].promise;
      responses[1].resolve(bankResponse(!lateFailure, "recent"));
      const recentReply = await recent;
      assertEquals(recentReply.status, 200);
      const expected = await recentReply.json();
      assertEquals(expected.token_masked, "recent********");
      if (delayedReadback) releaseReadback.resolve();
      else responses[0].resolve(bankResponse(lateFailure, "obsolete"));
      const lateReply = await old;
      assertEquals(lateReply.status, 200);
      const actual = await lateReply.json();
      assertEquals(events, ["begin-1", "remote-1", "begin-2", "remote-2"]);
      assertEquals(actual.state, expected.state);
      assertEquals(actual.last_error, expected.last_error);
      assertEquals(actual.warning_pending, expected.warning_pending);
      assertEquals(
        actual.token_masked,
        undefined,
        "discarded response cannot leak obsolete credential metadata",
      );
      assertEquals(
        actual.last_failure,
        undefined,
        "discarded response cannot project obsolete diagnostics",
      );
    });
  }
}
