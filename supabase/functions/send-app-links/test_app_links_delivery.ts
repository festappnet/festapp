import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { deliverAppLinks, isCsmOrganization } from "./appLinksDelivery.ts";

const input = {
  userId: "00000000-0000-0000-0000-000000000001",
  occasionId: 643,
  unitId: 27,
  organizationId: 9,
  deliveryEmail: "participant@example.test",
  appName: "CSM Ostrava",
  appLinks: '<p><a href="https://example.test">Otevřít</a></p>',
  fromEmail: "info@example.test",
};

Deno.test("application links require explicit tenant activation, never a hardcoded organization", () => {
  const before = Deno.env.get("APP_LINKS_ORGANIZATION_ID");
  try {
    Deno.env.delete("APP_LINKS_ORGANIZATION_ID");
    assertEquals(isCsmOrganization(9), false);
    Deno.env.set("APP_LINKS_ORGANIZATION_ID", "77");
    assertEquals(isCsmOrganization(77), true);
    assertEquals(isCsmOrganization(9), false);
  } finally {
    if (before === undefined) Deno.env.delete("APP_LINKS_ORGANIZATION_ID");
    else Deno.env.set("APP_LINKS_ORGANIZATION_ID", before);
  }
});

Deno.test("application links delivery supplies template links and brand and delegates post-actions to SQL", async () => {
  const calls: string[] = [];
  let emailInput: Record<string, unknown> | undefined;

  await deliverAppLinks(input, {
    deliverEmail(value) {
      calls.push("deliver");
      emailInput = value as unknown as Record<string, unknown>;
      return Promise.resolve();
    },
  });

  assertEquals(calls, ["deliver"]);
  assertEquals(emailInput?.templateCode, "APP_LINKS");
  assertEquals(emailInput?.recipientUser, input.userId);
  assertEquals(emailInput?.substitutions, { appLinks: input.appLinks, appName: input.appName });
});

Deno.test("failed or pending canonical application links delivery cannot claim success", async () => {
  await assertRejects(
    () =>
      deliverAppLinks(input, {
        deliverEmail: () => Promise.reject(new Error("email_pending")),
      }),
    Error,
    "email_pending",
  );
});
