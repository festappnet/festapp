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

Deno.test("inactive and executable lookalikes never become detected policy IDs", () => {
  const config = 'var complianz={"current_policy_id":"42"};';
  for (
    const html of [
      `<!-- <script>${config}</script> -->`,
      `<script>/* ${config} */</script>`,
      `<script>// ${config}</script>`,
      `<script>const example = '${config}';</script>`,
      `<script>function unused(){${config}}</script>`,
      `<script>if(false){${config}}</script>`,
      `<script type="application/json">${config}</script>`,
      `<script type="module">${config}</script>`,
      `<script src="/other.js">${config}</script>`,
      `<template><script>${config}</script></template>`,
      `<noscript><script>${config}</script></noscript>`,
      `<textarea><script>${config}</script></textarea>`,
      `<script>${config} complianz.current_policy_id="43";</script>`,
      `<script>${config} var complianz={</script>`,
      `<script>${config}</script><script>var complianz={</script>`,
    ]
  ) assertEquals(extractPolicyId(html), null, html);
  assertEquals(
    extractPolicyId(
      `<script>/* WordPress localized settings */ ${config}\n//# sourceURL=cmplz-js-extra</script>`,
    ),
    "42",
  );
});

Deno.test("maximum-size repeated unfinished declarations are rejected in one parse", () => {
  const html = `<script>${"var complianz={".repeat(69_000)}</script>`;
  assertEquals(html.length < MAX_HTML_BYTES, true);
  assertEquals(extractPolicyId(html), null);
});
