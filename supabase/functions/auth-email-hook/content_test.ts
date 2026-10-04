import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { authEmailContent, authEmailRecipients } from "./content.ts";
Deno.test("Auth actions preserve OTP, verification proof and encoded redirect without tracking", () => {
  for (
    const action of [
      "signup",
      "invite",
      "magiclink",
      "recovery",
      "email_change",
    ]
  ) {
    const content = authEmailContent({
      email_action_type: action,
      token: "123456",
      token_hash: "hash&proof",
      redirect_to: "https://app.example.invalid/path?next=a&b=c",
    }, "https://api.example.invalid");
    assert(content.html.includes("123456"));
    assert(content.html.includes("token=hash%26proof"));
    assert(content.html.includes(`type=${action}`));
    assert(content.html.includes("redirect_to=https%3A"));
    assert(!content.html.includes("tracking"));
  }
  assert(
    !authEmailContent({
      email_action_type: "reauthentication",
      token: "123456",
    }, "https://api.example.invalid").html.includes("href"),
  );
  assertThrows(() =>
    authEmailContent(
      { email_action_type: "recovery", token: "123456" },
      "https://api.example.invalid",
    )
  );
  assertThrows(() =>
    authEmailContent({
      email_action_type: "recovery",
      token: "123456",
      token_hash: "proof",
    }, "http://api-gw:8000")
  );
});
Deno.test("secure email change keeps separate current and new proofs", () => {
  const data = {
    email_action_type: "email_change",
    token: "111111",
    token_hash: "new-proof",
    token_new: "222222",
    token_hash_new: "old-proof",
  };
  const rows = authEmailRecipients({
    email: "old@example.invalid",
    new_email: "new@example.invalid",
  }, data);
  assertEquals(rows.map((r) => r.to), [
    "new@example.invalid",
    "old@example.invalid",
  ]);
  assertEquals(rows[0].data.token_hash, "new-proof");
  assertEquals(rows[1].data.token_hash, "old-proof");
});
