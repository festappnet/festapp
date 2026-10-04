import {assertEquals} from "jsr:@std/assert@1";
import {createRateHandler} from "./handler.ts";
const day = "2026-10-02";
const request = () => new Request("https://example.invalid", {method: "POST", headers: {Authorization: "Bearer test"}});
Deno.test("rates require a verified user before external access", async () => {
  let calls = 0;
  const handler = createRateHandler({authorize: () => Promise.resolve(false), fetch: () => {calls++; throw Error();}});
  assertEquals((await handler(request())).status, 401);
  assertEquals(calls, 0);
  assertEquals((await handler(new Request("https://example.invalid", {method:"OPTIONS"}))).status,200);
});
Deno.test("CNB rates preserve quantity and date, cache and reject stale snapshots", async () => {
  let calls = 0;
  let time = Date.parse("2026-10-03");
  const handler = createRateHandler({authorize: () => Promise.resolve(true), now: () => time,
    fetch: () => {calls++; return Promise.resolve(new Response(JSON.stringify({rates:[{validFor:day,currencyCode:"JPY",amount:100,rate:14.123}]})));}});
  const result = await (await handler(request())).json();
  assertEquals(result.rates.JPY, {amount:"100",rate:"14.123"});
  assertEquals(result.date,day);
  await handler(request()); assertEquals(calls,1);
  time += 8*86400000;
  assertEquals((await handler(request())).status,503);
});
