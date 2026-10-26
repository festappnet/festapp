import { assertEquals } from "jsr:@std/assert@1";
import {
  hasSingleTicketOrderPayload,
  resolveTicketOrderCommandIdentity,
} from "./commandIdentity.ts";

Deno.test("preserves command identity from current clients", () => {
  assertEquals(
    resolveTicketOrderCommandIdentity("command", "client", null),
    { commandId: "command", clientId: "client" },
  );
});

Deno.test("legacy requests cannot create a fresh checkout identity on each retry", () => {
  assertEquals(
    resolveTicketOrderCommandIdentity(undefined, undefined, null),
    null,
  );
  assertEquals(
    resolveTicketOrderCommandIdentity("command", undefined, null),
    null,
  );
});

Deno.test("replacement orders remain fail-closed without client identity", () => {
  assertEquals(
    resolveTicketOrderCommandIdentity(undefined, undefined, { spotIds: [] }),
    null,
  );
});

Deno.test("waitlist acceptance includes its ordinary UI orderDetails without mixing independent order intents", () => {
  assertEquals(
    hasSingleTicketOrderPayload({
      orderDetails: {},
      waitlistAcceptance: { offerId: "fixture" },
    }),
    true,
  );
  assertEquals(hasSingleTicketOrderPayload({ waitlistAcceptance: {} }), false);
  assertEquals(
    hasSingleTicketOrderPayload({
      orderDetails: {},
      waitlistAcceptance: {},
      replacement: {},
    }),
    false,
  );
  assertEquals(hasSingleTicketOrderPayload({ administrativeOrder: {} }), true);
  assertEquals(
    hasSingleTicketOrderPayload({ administrativeOrder: {}, orderDetails: {} }),
    false,
  );
});
