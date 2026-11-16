import { assertEquals } from "jsr:@std/assert";
import { extractPolicyId, MAX_HTML_BYTES } from "./policy.ts";

Deno.test("extract WordPress localized single site, multisite and minified config", () => {
  for (
    const [prefix, declaration] of [["cmplz_", "var"], ["cmplz_rt_", "var"], [
      "cmplz_2_",
      "const",
    ]]
  ) {
    const config = {
      prefix,
      current_policy_id: "42",
      categories: { statistics: "statistics", marketing: "marketing" },
      placeholdertext: "<div>{service}</div>",
      url: "https://example.com/wp-json/complianz/v1/",
    };
    assertEquals(
      extractPolicyId(
        `<script id="cmplz-cookiebanner-js-extra">${declaration} complianz=${
          JSON.stringify(config)
        };</script>`,
      ),
      "42",
    );
  }
  assertEquals(
    extractPolicyId(
      '<script>let complianz = {"current_policy_id":42};</script>',
    ),
    "42",
  );
});
Deno.test("missing, executable, ambiguous, invalid and oversized data fail closed", () => {
  for (
    const html of [
      "",
      '<p>var complianz = {"current_policy_id":"42"}</p>',
      '<script>var other = {"current_policy_id":"42"};</script>',
      '<script>var complianz = {"current_policy_id":run()};</script>',
      '<script>var complianz = {"current_policy_id":"0"};</script>',
      '<script>var complianz = {"current_policy_id":"42"}; var complianz = {"current_policy_id":"43"};</script>',
      "x".repeat(MAX_HTML_BYTES + 1),
    ]
  ) assertEquals(extractPolicyId(html), null);
});
