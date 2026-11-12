import { assertEquals } from "jsr:@std/assert@1";
import { sendEmailAttempt } from "./emailSender.ts";
Deno.test("recipient digest uses the sole sender without tenant tags or engagement tracking; unknown never retries blindly", async () => {
  const config = {
    region: "fixture",
    accessKey: "fake",
    secretKey: "fake",
    sender: "sender@example.test",
    transactionalSet: "transactional",
    securitySet: "security",
    maxBytes: 1000000,
  };
  const calls: string[] = [];
  let unknown = false, sends = 0;
  const result = await sendEmailAttempt("attempt", "token", {
    config,
    rpc: async (name, args) => {
      calls.push(name);
      if (name === "begin_email_send") {
        return unknown ? { disposition: "replay", state: "unknown" } : {
          disposition: "send",
          message: {
            message_id: "m",
            organization: null,
            message_kind: "admin_notification_digest",
            tracking_policy: "disabled",
            recipient: "recipient@example.test",
            prepared: {},
          },
        };
      }
      if (name === "finish_email_attempt") {
        assertEquals(args?.p_outcome, "unknown");
        unknown = true;
      }
    },
    open: async () => ({
      from: "Festapp <sender@example.test>",
      to: "recipient@example.test",
      subject: "Summary",
      html: "Summary",
      replyTo: "sender@example.test",
      attachments: [],
    }),
    send: async (_message, tags, sensitive, engagement) => {
      sends++;
      assertEquals("organization_id" in tags, false);
      assertEquals(sensitive, true);
      assertEquals(engagement, false);
      throw new Error("ambiguous transport");
    },
  });
  assertEquals(result.disposition, "unknown");
  const replay = await sendEmailAttempt("attempt", "token", {
    config,
    rpc: async () => ({ disposition: "replay", state: "unknown" }),
    open: async () => {
      throw new Error("unexpected second preparation");
    },
    send: async () => {
      throw new Error("unexpected second provider call");
    },
  });
  assertEquals(replay.disposition, "replay");
  assertEquals(sends, 1);
  assertEquals(calls, ["begin_email_send", "finish_email_attempt"]);
});
