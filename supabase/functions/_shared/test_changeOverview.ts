import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  generateChangeOverview,
  type OrderChangeSummary,
} from "./changeOverview.ts";
const fixture = JSON.parse(
  Deno.readTextFileSync(
    new URL(
      "../../../test/fixtures/order_changes/cancellation_and_product_edit.json",
      import.meta.url,
    ),
  ),
) as OrderChangeSummary;
for (const lang of ["cs", "en"] as const) {
  Deno.test(`canonical cancellation and product edit render distinctly (${lang})`, () => {
    const html = generateChangeOverview(fixture, lang);
    assertStringIncludes(html, lang === "cs" ? "(Storno)" : "(Cancelled)");
    assertStringIncludes(html, "FIRST");
    assertStringIncludes(html, "SURVIVOR");
    assertEquals(
      html.includes(lang === "cs" ? "Odebrané položky" : "Removed items"),
      false,
    );
    assertStringIncludes(html, lang === "cs" ? "Celková cena" : "Total price");
  });
}
Deno.test("summary renderer escapes ticket symbols and product labels", () => {
  const value = structuredClone(fixture);
  value.cancelledTickets[0].ticket_symbol = "<img src=x onerror=alert(1)>";
  value.cancelledTickets[0].products![0].title = "<script>bad</script>";
  const html = generateChangeOverview(value);
  assertEquals(html.includes("<script>"), false);
  assertEquals(html.includes("<img src=x"), false);
  assertStringIncludes(html, "&lt;script&gt;bad&lt;/script&gt;");
});
Deno.test("empty/free cancelled ticket still has a labelled section", () => {
  const value = structuredClone(fixture);
  value.cancelledTickets[0].products = [];
  assertStringIncludes(generateChangeOverview(value), "Vstupenka FIRST");
});
Deno.test("unchanged summary renders nothing and missing version fails closed", () => {
  assertEquals(generateChangeOverview({ ...fixture, hasChanges: false }), "");
  assertThrows(() => generateChangeOverview({ ...fixture, version: 2 }));
});
Deno.test("product removal on a surviving ticket is never rendered as cancellation", () => {
  const value = structuredClone(fixture);
  const product = value.cancelledTickets[0].products![0];
  value.cancelledTickets = [];
  value.productChanges = [{
    id: 2,
    ticket_symbol: "SURVIVOR",
    added: [],
    removed: [product],
    changed: [],
  }];
  const html = generateChangeOverview(value);
  assertEquals(html.includes("(Storno)"), false);
  assertStringIncludes(html, "- Místo");
  assertStringIncludes(html, "SURVIVOR");
});
Deno.test("multiple cancellations and mixed product additions/removals keep separate context", () => {
  const value = structuredClone(fixture);
  value.cancelledTickets.push({ id: 3, ticket_symbol: "THIRD", products: [] });
  value.productChanges[0].added = [{ id: 8, title: "New item", price: 5 }];
  value.productChanges[0].removed = [{ id: 9, title: "Old item", price: 2 }];
  const html = generateChangeOverview(value);
  for (
    const label of [
      "Vstupenka FIRST",
      "Vstupenka THIRD",
      "Vstupenka SURVIVOR",
      "+ New item",
      "- Old item",
    ]
  ) assertStringIncludes(html, label);
});

Deno.test("email overview retains original colors and layout without new colored cards", () => {
  const value = structuredClone(fixture);
  value.productChanges[0].added = [{ id: 8, title: "Added product", price: 5 }];
  value.productChanges[0].removed = [{
    id: 9,
    title: "Removed product",
    price: 2,
  }];
  const html = generateChangeOverview(value);
  for (
    const style of [
      "color: #991b1b",
      "color: #166534",
      "color: #d97706",
      "color:#6b7280",
      "background-color: #f9fafb",
      "border-top: 1px solid #e2e8f0",
      "font-size: 18px",
    ]
  ) assertStringIncludes(html, style);
  for (const label of ["(Storno)", "+ Added product", "- Removed product"]) {
    assertStringIncludes(html, label);
  }
  for (const newColor of ["#fef2f2", "#f0fdf4", "#fffbeb", "#1e3a5f"]) {
    assertEquals(html.includes(newColor), false);
  }
});

Deno.test("each change block starts with its ticket and only cancelled tickets are struck through", () => {
  const html = generateChangeOverview(fixture);
  assertStringIncludes(
    html,
    'text-decoration: line-through; color: #991b1b;">Vstupenka FIRST</span>',
  );
  assertStringIncludes(html, "<span>Vstupenka SURVIVOR</span>");
  assertEquals(html.includes("Stornované vstupenky"), false);
  assertEquals(html.includes("Změny produktů na vstupence"), false);
  assertEquals(html.includes("Změna ceny položek"), false);
  const neutral = structuredClone(fixture);
  neutral.removedTickets = neutral.cancelledTickets;
  neutral.cancelledTickets = [];
  const neutralHtml = generateChangeOverview(neutral);
  assertStringIncludes(neutralHtml, "(Odebraná)");
  assertEquals(neutralHtml.includes("text-decoration: line-through"), false);
});
