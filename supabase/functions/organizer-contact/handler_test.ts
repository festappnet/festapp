import { assertEquals } from "jsr:@std/assert";
import { openEmail } from "../_shared/emailPayload.ts";
import { contactIntent } from "./contact_intent.ts";
import { organizerContactHandler } from "./handler.ts";

const origin = "https://vstupenky.online";
const body = {
  id: "6fabca3a-47cb-48fb-b829-d68d97e639ec",
  email: "host@example.com",
  message: "Dobrý den, potřebuji poradit.",
};
const request = (value: unknown, caller = origin) =>
  new Request("https://api.festapp.net/functions/v1/organizer-contact", {
    method: "POST",
    headers: { "Content-Type": "application/json", origin: caller },
    body: JSON.stringify(value),
  });

Deno.test("only valid bounded contact payloads reach the forwarding boundary", async () => {
  let count = 0;
  const handler = organizerContactHandler((contact) => {
    count++;
    assertEquals(contact, body);
    return Promise.resolve("accepted");
  });
  assertEquals(
    (await handler(request(body, "https://other.example"))).status,
    403,
  );
  assertEquals(
    (await handler(request({ ...body, email: "a@b.cz\r\nBcc: x@b.cz" })))
      .status,
    400,
  );
  assertEquals(
    (await handler(request({ ...body, message: " ".repeat(10) }))).status,
    400,
  );
  assertEquals(
    (await handler(request({ ...body, message: "x".repeat(10_000) }))).status,
    400,
  );
  const accepted = await handler(
    request({ ...body, message: ` ${body.message} ` }),
  );
  assertEquals(accepted.status, 202);
  assertEquals(accepted.headers.get("cache-control"), "no-store");
  assertEquals(count, 1);
});

Deno.test("the client can distinguish throttling, conflicts and temporary outages", async () => {
  const error = (code: string) =>
    organizerContactHandler(() => Promise.reject({ code }));
  assertEquals((await error("PT429")(request(body))).status, 429);
  assertEquals((await error("offline")(request(body))).status, 503);
  const conflict = organizerContactHandler(() => Promise.resolve("conflict"));
  assertEquals((await conflict(request(body))).status, 409);
});

Deno.test("forwarded email is sealed with the fixed target, safe text and visitor reply address", async () => {
  const previous = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("x".repeat(32)));
  try {
    const contact = { ...body, message: "<b>Zpráva</b> & text\ndruhý řádek" };
    const first = await contactIntent(contact, "noreply@example.invalid");
    const second = await contactIntent(contact, "noreply@example.invalid");
    assertEquals(first.p_content_hash, second.p_content_hash);
    assertEquals(await openEmail(first.p_sealed), {
      from: "noreply@example.invalid",
      to: "info@vstupenky.online",
      subject: "Dotaz z formuláře vstupenky.online",
      html:
        "<p>E-mail pro odpověď: host@example.com</p><p>&lt;b&gt;Zpráva&lt;/b&gt; &amp; text<br>druhý řádek</p>",
      replyTo: "host@example.com",
      attachments: [],
    });
  } finally {
    if (previous === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
    else Deno.env.set("EMAIL_PAYLOAD_KEY", previous);
  }
});
