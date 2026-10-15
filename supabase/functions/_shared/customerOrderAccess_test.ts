import assert from "node:assert/strict";
import { prepareOrderOverviewSource } from "./waitlistEmail.ts";
import { openOrderOverviewUrl } from "./customerOrderAccess.ts";
const context = { orderId: 12, recipient: "test@example.invalid", organization: 1, occasion: 2, unit: 3,
  occasionTitle: "Synthetic", participantCount: 2, formLink: "test", webLink: "https://tenant.example.invalid/" };
Deno.test("overview encrypted source binds root and tenant without leaking token into SQL", async () => {
  const previous = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set("EMAIL_PAYLOAD_KEY", btoa(String.fromCharCode(...new Uint8Array(32).fill(19))));
  try {
    const source = await prepareOrderOverviewSource(context);
    const url = new URL(await openOrderOverviewUrl(context, source));
    assert.equal(url.pathname, "/form/test"); assert.equal(url.hash, "");
    assert.match(url.search, /^\?order_id=12&token=[0-9a-f]{64}$/);
    const token = new URLSearchParams(url.search).get("token")!;
    assert.equal(JSON.stringify(source).includes(token), false);
    for (const changed of [{ organization: 9 }, { orderId: 99 }, { formLink: "other" }, { recipient: "other@example.invalid" }]) {
      await assert.rejects(() => openOrderOverviewUrl({ ...context, ...changed }, source));
    }
    await assert.rejects(() => openOrderOverviewUrl(context, { ...source, contentHash: "f".repeat(64) }));
    await assert.rejects(() => openOrderOverviewUrl({ ...context, webLink: "http://public.invalid/" }, source));
    assert.equal(await openOrderOverviewUrl(context, source), url.href);
  } finally {
    if (previous === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY"); else Deno.env.set("EMAIL_PAYLOAD_KEY", previous);
  }
});
