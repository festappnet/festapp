import { renderEmail } from "../_shared/emailDelivery.ts";
import { emailVariableContract } from "../_shared/emailVariables.ts";
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sendTeamAccessNotice } from "./teamAccessNotice.ts";

Deno.test("existing editor/viewer/manager invitations deliver access notice without password or code", async () => {
  for (
    const access of [{ is_editor: true }, { is_editor_view: true }, {
      is_manager: true,
    }]
  ) {
    let authorized = false;
    const sent: unknown[] = [];
    await sendTeamAccessNotice({
      access: {
        ...access,
        capabilities: { "emails.team_access_notice": true },
      },
      occasion: {
        id: 7,
        unit: 3,
        organization: 2,
        link: "event",
        title: "<Evening>",
      },
      user: "user",
      email: "team@example.org",
      defaultUrl: "https://tenant.test",
      appName: "App",
      requestId: "retry",
    }, {
      authorize: async () => {
        authorized = true;
      },
      deliver: async (input) => {
        assertEquals(authorized, true);
        sent.push(input);
      },
    });
    assertEquals(sent.length, 1);
    const message = sent[0] as {
      templateCode: string;
      substitutions: Record<string, string>;
    };
    assertEquals(message.templateCode, "TEAM_ACCESS_NOTICE");
    assertEquals(
      message.substitutions.occasionAdminUrl,
      "https://tenant.test/event/admin",
    );
    assertEquals(message.substitutions.occasionTitle, "<Evening>");
    assertEquals("password" in message.substitutions, false);
    assertEquals("code" in message.substitutions, false);
  }
});
Deno.test("unauthorized notice never delivers; participants stay out of team path", async () => {
  let sent = false;
  await assertRejects(() =>
    sendTeamAccessNotice({
      access: {
        is_editor: true,
        capabilities: { "emails.team_access_notice": true },
      },
      occasion: {
        id: 7,
        unit: 3,
        organization: 2,
        link: "event",
        title: "Event",
      },
      user: "user",
      email: "team@example.org",
      defaultUrl: "https://tenant.test",
      appName: "App",
      requestId: "retry",
    }, {
      authorize: () => Promise.reject(new Error("forbidden")),
      deliver: async () => {
        sent = true;
      },
    })
  );
  assertEquals(sent, false);
});

Deno.test("team access notice uses the canonical catalog and common escaping", async () => {
  let rendered: { subject: string; html: string } | undefined;
  await sendTeamAccessNotice({
    access: {
      is_editor: true,
      capabilities: { "emails.team_access_notice": true },
    },
    occasion: {
      id: 7,
      unit: 3,
      organization: 2,
      link: "event",
      title: "Večer <E>",
    },
    user: "user",
    email: "team@example.invalid",
    defaultUrl: "https://tenant.test",
    appName: "A & B",
    requestId: "fixture",
  }, {
    authorize: async () => {},
    deliver: async (input) => {
      const available = new Set<string>(
        emailVariableContract.templates.TEAM_ACCESS_NOTICE,
      );
      assert(
        Object.keys(input.substitutions).every((code) => available.has(code)),
      );
      rendered = await renderEmail(
        input,
        async () => ({
          template: {
            id: 1,
            subject: "{{appName}} - {{occasionTitle}}",
            html:
              '<h2>{{occasionTitle}}</h2><p>{{appName}}</p><a href="{{occasionAdminUrl}}">{{roleLabel}}</a>',
          },
        }),
      );
    },
  });
  assert(rendered);
  assertEquals(rendered.subject, "A & B - Večer <E>");
  assert(rendered.html.includes("A &amp; B"));
  assert(rendered.html.includes("Večer &lt;E&gt;"));
  assert(!rendered.html.includes("&amp;amp;"));
});
