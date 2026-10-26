import { assertEquals } from "jsr:@std/assert@1";
import { buildNotificationPayload } from "./notificationPayload.ts";

const base = {
  appId: "existing-app",
  defaultUrl: "https://example.test",
  occasionLink: "csmostrava2026",
  targetPath: "news",
  heading: "Heading",
  content: "Content",
};

function matchesFilters(
  filters: Array<{ field?: string; key?: string; value?: string }>,
  tags: Record<string, string>,
) {
  return filters
    .filter((filter) => filter.field === "tag")
    .every((filter) => tags[filter.key!] === filter.value);
}

Deno.test("broadcast requires both exact CSM audience tags", () => {
  const payload = buildNotificationPayload(base);
  if (!("filters" in payload)) {
    throw new Error("Broadcast payload must use tag filters");
  }
  const filters = payload.filters;

  assertEquals(
    matchesFilters(filters, {
      app_generation: "csm_ostrava_2026_v1",
      occasion: "csmostrava2026",
    }),
    true,
  );
  assertEquals(matchesFilters(filters, { occasion: "csmostrava2026" }), false);
  assertEquals(
    matchesFilters(filters, {
      app_generation: "csm_ostrava_2026_v1",
      occasion: "wrong-occasion",
    }),
    false,
  );
  assertEquals(
    matchesFilters(filters, {
      app_generation: "jm_2025",
      occasion: "csmostrava2026",
    }),
    false,
  );
  assertEquals("included_segments" in payload, false);
});

Deno.test("direct recipient delivery uses only external_id", () => {
  const payload = buildNotificationPayload({ ...base, recipient: "user-uuid" });
  if (!("include_aliases" in payload)) {
    throw new Error("Direct payload must use an external ID alias");
  }

  assertEquals(payload.include_aliases, { external_id: ["user-uuid"] });
  assertEquals("filters" in payload, false);
  assertEquals("included_segments" in payload, false);
});

Deno.test("web notifications use the deployed application icon", () => {
  const expectedIcon = "https://example.test/notification-icon-256x256.png";

  for (const payload of [
    buildNotificationPayload(base),
    buildNotificationPayload({ ...base, recipient: "user-uuid" }),
  ]) {
    assertEquals(payload.chrome_web_icon, expectedIcon);
    assertEquals(payload.firefox_icon, expectedIcon);
  }
});
