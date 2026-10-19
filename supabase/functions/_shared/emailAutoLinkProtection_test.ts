import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import { renderEmail } from "./emailDelivery.ts";
import { generateFullOrder } from "./orderOverview.ts";

Deno.test("rendered payment and contact text has client auto-link protection without altering copied values", async () => {
  const card = generateFullOrder(
    { email: "customer@example.invalid" },
    [],
    [],
    "cs",
    "5N5Q2Q1J9X",
  );
  const body = "<p>Účet <strong>2502719268/2010</strong>, VS 6734.</p>" + card;
  const action =
    '<a href="https://example.invalid/order?token=original">Order status</a>';
  const email = await renderEmail(
    {
      to: "customer@example.invalid",
      context: { organization: 3 },
      substitutions: { details: body },
      template: {
        id: 1,
        subject: "Order 2502719268",
        html: "{{details}}" + action,
      },
    },
    async () => ({
      wrapper: { html: "<html><head></head><body>{{content}}</body></html>" },
    }),
  );
  assertMatch(
    email.html,
    /class="festapp-plain-value">2502719268\/2010<\/span>/,
  );
  assertMatch(
    email.html,
    /class="festapp-plain-value">customer@example.invalid<\/span>/,
  );
  assertMatch(
    email.html,
    /\.festapp-plain-value a\s*\{[^}]*pointer-events:none!important/,
  );
  assert(email.html.includes(action));
  assertEquals((email.html.match(/<a\b/g) || []).length, 1);
  assert(
    !/[\u200b\u200c\u200d\u2060]|&#(?:8203|8204|8205|8288);/.test(email.html),
  );
  assertEquals(email.subject, "Order 2502719268");
  assertEquals(email.to, "customer@example.invalid");
});

import { protectEmailAutoLinks } from "./emailAutoLinkProtection.ts";

Deno.test("author links, attributes, comments and raw styles remain exact", () => {
  const link =
    '<a href="mailto:author@example.invalid" style="color:red">author@example.invalid 2502719268/2010</a>';
  const untouched = '<head><style>.x {content:"123456789"}</style></head>' +
    link + "<!-- 123456789 -->" +
    '<img alt="a > 123456789" src="https://example.invalid/image">';
  assertEquals(protectEmailAutoLinks(untouched), untouched);
  const protectedHtml = protectEmailAutoLinks(
    untouched + "<b>2502719268/2010</b>",
  );
  assert(protectedHtml.includes(link));
  assert(
    protectedHtml.includes(
      '<img alt="a > 123456789" src="https://example.invalid/image">',
    ),
  );
  assertEquals(protectEmailAutoLinks(protectedHtml), protectedHtml);
});
