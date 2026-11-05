import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { AuthError } from "./authError.ts";
import {
  drainNotifications,
  notificationHandler,
  notificationRpc,
} from "./notificationDispatcher.ts";
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status });
Deno.test("notification worker authorizes before any SQL and never accepts a caller's budget", async () => {
  const calls: string[] = [];
  const handler = notificationHandler({
    authorize: () => Promise.reject(new AuthError("denied", 403)),
    rpc: async (name) => {
      calls.push(name);
      return 0;
    },
  });
  assertEquals(
    (await handler(
      new Request("https://worker.invalid", { method: "POST", body: "{}" }),
    )).status,
    401,
  );
  assertEquals(
    (await handler(
      new Request("https://worker.invalid", {
        method: "POST",
        body: '{"requestSecret":"wrong","maxCalls":999999}',
      }),
    )).status,
    403,
  );
  assertEquals(
    (await handler(new Request("https://worker.invalid"))).status,
    405,
  );
  assertEquals(calls, []);
});
Deno.test("actual RPC transport commits each work class separately and validates receipts", async () => {
  const calls: { name: string; limit?: number }[] = [];
  const responses = [2, 1, 0, 0, 0, 0];
  const rpc = notificationRpc(
    "https://local.invalid",
    "fixture-service-key",
    (async (url, init) => {
      assertEquals(
        new Headers(init?.headers).get("authorization"),
        "Bearer fixture-service-key",
      );
      const name = String(url).split("/").at(-1)!;
      calls.push({ name, limit: JSON.parse(String(init?.body)).p_limit });
      return json(responses.shift());
    }) as typeof fetch,
  );
  const result = await drainNotifications(rpc);
  assertEquals({
    delivered: result.delivered,
    prepared: result.prepared,
    views: result.views,
    idle: result.idle,
  }, { delivered: 2, prepared: 1, views: 0, idle: true });
  assertEquals(calls.map((x) => x.name), [
    "project_notification_center",
    "prepare_notification_center",
    "prepare_notification_center_views",
    "project_notification_center",
    "prepare_notification_center",
    "prepare_notification_center_views",
  ]);
  assertEquals(calls.map((x) => x.limit), [500, 100, 100, 500, 100, 100]);
});
Deno.test("HTTP failure after committed delivery retries through the same real executor without a fabricated success", async () => {
  let fail = true, delivered = false;
  const calls: string[] = [];
  const rpc = notificationRpc(
    "https://local.invalid",
    "fixture-key",
    (async (url) => {
      const name = String(url).split("/").at(-1)!;
      calls.push(name);
      if (name === "project_notification_center" && !delivered) {
        delivered = true;
        return json(1);
      }
      if (name === "prepare_notification_center" && fail) {
        fail = false;
        return json({ private: "must not escape" }, 500);
      }
      return json(0);
    }) as typeof fetch,
  );
  const handler = notificationHandler({
    authorize: async () => undefined,
    rpc,
  });
  const request = () =>
    new Request("https://worker.invalid", {
      method: "POST",
      body: '{"requestSecret":"fixture"}',
    });
  const failed = await handler(request());
  assertEquals(failed.status, 500);
  assertEquals(await failed.json(), { error: "notification_worker_failed" });
  const recovered = await handler(request());
  assertEquals(recovered.status, 200);
  assertEquals((await recovered.json()).delivered, 0);
  assertEquals(
    calls.filter((name) => name.includes("read") || name.includes("open")),
    [],
  );
});
Deno.test("malformed SQL receipts fail closed; a bounded nonidle drain re-wakes durable work", async () => {
  await assertRejects(
    () => drainNotifications(async () => "0"),
    Error,
    "notification_invalid_work_receipt",
  );
  const calls: string[] = [];
  const result = await drainNotifications(async (name) => {
    calls.push(name);
    return name === "project_notification_center" ? 1 : 0;
  }, { maxCalls: 1 });
  assertEquals(result.idle, false);
  assertEquals(calls.at(-1), "wake_notification_center");
});
Deno.test("work is attached to runtime lifetime independently of the pg_net response connection", async () => {
  let attached = false;
  const work: Promise<unknown>[] = [];
  const handler = notificationHandler({
    authorize: async () => undefined,
    rpc: async () => {
      await Promise.resolve();
      assertEquals(attached, true);
      return 0;
    },
    waitUntil: (promise) => {
      attached = true;
      work.push(promise);
    },
  });
  const result = await handler(
    new Request("https://worker.invalid", {
      method: "POST",
      body: '{"requestSecret":"fixture"}',
    }),
  );
  assertEquals(result.status, 200);
  await Promise.all(work);
  assertEquals(work.length, 1);
});
