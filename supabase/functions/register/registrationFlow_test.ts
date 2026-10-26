import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { finishRegistration } from "./registrationFlow.ts";

const input = {
  userEmail: "person@example.test",
  organizationId: 9,
  appName: "CSM Ostrava",
  code: "123456",
  platformLinksHtml: "<a>Web</a>",
};

Deno.test("registration does not send credentials when the domain rejects creation", async () => {
  const sent: Array<Record<string, unknown>> = [];
  const result = await finishRegistration({
    ...input,
    creationResult: {
      data: {
        code: 403,
        error: "Registration is disabled for this organization",
      },
      error: null,
    },
  }, async (message) => {
    sent.push(message);
  });

  assertEquals(result, {
    body: {
      code: 403,
      error: "Registration is disabled for this organization",
    },
    status: 200,
  });
  assertEquals(sent, []);
});

Deno.test("registration sends credentials only after a created user is confirmed", async () => {
  const sent: Array<Record<string, unknown>> = [];
  const result = await finishRegistration({
    ...input,
    creationResult: {
      data: { code: 200, id: "user-id" },
      error: null,
    },
  }, async (message) => {
    sent.push(message);
  });

  assertEquals(result, {
    body: { email: input.userEmail, code: 200 },
    status: 200,
  });
  assertEquals(sent.length, 1);
  assertEquals(sent[0].recipientUser, "user-id");
});

Deno.test("registration rejects success without an auditable user id", async () => {
  const sent: Array<Record<string, unknown>> = [];
  const result = await finishRegistration({
    ...input,
    creationResult: { data: { code: 200 }, error: null },
  }, async (message) => {
    sent.push(message);
  });

  assertEquals(result, {
    body: { error: "Invalid created user identifier" },
    status: 500,
  });
  assertEquals(sent, []);
});
