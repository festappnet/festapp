import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseLoginQr, parseManualLoginCode } from "./qr.ts";
Deno.test("accepts only typed login QR", () => {
  assertEquals(
    parseLoginQr(`festapp-login:v1:42:${"A".repeat(43)}`)?.occasion,
    42,
  );
  assertEquals(parseLoginQr("550e8400-e29b-41d4-a716-446655440000"), null);
  assertEquals(parseLoginQr("ticket:v1:ABC"), null);
  assertEquals(parseLoginQr(`festapp-login:v2:42:${"A".repeat(43)}`), null);
});

Deno.test("manual login code is case and separator insensitive", () => {
  assertEquals(parseManualLoginCode(42, " k7m4-p9q2 "), {
    occasion: 42,
    token: "K7M4P9Q2",
  });
  assertEquals(parseManualLoginCode(42, "K7M4 P9Q2"), {
    occasion: 42,
    token: "K7M4P9Q2",
  });
  assertEquals(parseManualLoginCode(42, "K7M4P9O2"), null);
  assertEquals(parseManualLoginCode(0, "K7M4P9Q2"), null);
});
