import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type AuthoringContextDependencies,
  authoringContextResponse,
} from "./authoringContext.ts";
const input = {
  action: "authoringContext",
  entityType: "occasion",
  entityId: 42,
  templateCode: "TICKET_ORDER_REMINDER",
};
const catalog = {
  occasion: { id: 42 },
  unit: { id: 8 },
  organization: { id: 3 },
  templates: [{ code: input.templateCode }],
};
function fixture(overrides: Partial<AuthoringContextDependencies> = {}) {
  const calls: unknown[] = [];
  const dependencies: AuthoringContextDependencies = {
    senderAddress: "info@festapp.net",
    catalog: async (...args) => {
      calls.push(["catalog", ...args]);
      return catalog;
    },
    resolve: async (...args) => {
      calls.push(["resolve", ...args]);
      return {
        wrapper: { html: '<div style="padding:24px">{{content}}</div>' },
      };
    },
    ...overrides,
  };
  return { dependencies, calls };
}
Deno.test("authoring metadata requires authentication before any backend read", async () => {
  const { dependencies, calls } = fixture();
  assertEquals(
    (await authoringContextResponse(input, "", dependencies)).status,
    401,
  );
  assertEquals(calls, []);
});
Deno.test("authoring metadata validates scope and code before reads", async () => {
  const { dependencies, calls } = fixture();
  for (
    const invalid of [{ entityType: "organization" }, { entityId: -1 }, {
      templateCode: "../bad",
    }]
  ) {
    assertEquals(
      (await authoringContextResponse(
        { ...input, ...invalid },
        "Bearer caller",
        dependencies,
      )).status,
      400,
    );
  }
  assertEquals(calls, []);
});
Deno.test("a denied catalog never reaches service-role wrapper resolution", async () => {
  const { dependencies, calls } = fixture({ catalog: async () => null });
  assertEquals(
    (await authoringContextResponse(input, "Bearer denied", dependencies))
      .status,
    403,
  );
  assertEquals(calls, []);
});
Deno.test("authoring metadata derives hierarchy only from authorized catalog", async () => {
  const { dependencies, calls } = fixture();
  const response = await authoringContextResponse(
    { ...input, organization: 999, unit: 999 },
    "Bearer caller",
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(calls, [["catalog", "Bearer caller", "occasion", 42], [
    "resolve",
    input.templateCode,
    { organization: 3, unit: 8, occasion: 42 },
  ]]);
  const result = await response.json();
  assertEquals(result.senderAddress, "info@festapp.net");
  assertStringIncludes(result.wrapperHtml, "padding:24px");
  assertEquals(Object.keys(result).sort(), ["senderAddress", "wrapperHtml"]);
});
Deno.test("missing or mismatched template scope never resolves a wrapper", async () => {
  for (
    const record of [{ ...catalog, occasion: { id: 99 } }, {
      ...catalog,
      templates: [],
    }]
  ) {
    const { dependencies, calls } = fixture({ catalog: async () => record });
    assertEquals(
      (await authoringContextResponse(input, "Bearer caller", dependencies))
        .status,
      404,
    );
    assertEquals(calls, []);
  }
});
Deno.test("unit-only metadata cannot resolve an occasion wrapper", async () => {
  const { dependencies, calls } = fixture();
  const response = await authoringContextResponse(
    { ...input, entityType: "unit", entityId: 8 },
    "Bearer caller",
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals(calls[1], ["resolve", input.templateCode, {
    organization: 3,
    unit: 8,
  }]);
});
Deno.test("unavailable runtime sender or resolver fails without a fabricated sender", async () => {
  for (
    const override of [{ senderAddress: "" }, {
      resolve: async () => {
        throw new Error("offline");
      },
    }]
  ) {
    const { dependencies } = fixture(override);
    const response = await authoringContextResponse(
      input,
      "Bearer caller",
      dependencies,
    );
    assertEquals(response.status, 503);
    assertEquals((await response.json()).senderAddress, undefined);
  }
});
