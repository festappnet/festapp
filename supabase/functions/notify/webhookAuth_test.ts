import { assertEquals } from "jsr:@std/assert";
import { webhookTokenMatches } from "./webhookAuth.ts";

Deno.test("notification webhook requires the exact bearer token", async () => {
  assertEquals(await webhookTokenMatches("Bearer expected", "expected"), true);
  assertEquals(await webhookTokenMatches("Bearer wrong", "expected"), false);
  assertEquals(await webhookTokenMatches("Basic expected", "expected"), false);
  assertEquals(await webhookTokenMatches(null, "expected"), false);
});
