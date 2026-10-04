export function normalizeSesEvents(root: any, topic: string, _id: string) {
  const kind: Record<string, string> = {
    Send: "send",
    Delivery: "delivery",
    DeliveryDelay: "delay",
    Bounce: "bounce",
    Complaint: "complaint",
    Reject: "reject",
    RenderingFailure: "rendering_failure",
    Open: "open",
    Click: "click",
  };
  const raw = root?.eventType ?? root?.notificationType, type = kind[raw];
  if (!type || typeof root.mail?.messageId !== "string") {
    throw new Error("invalid_ses_event");
  }
  const detail = root[
    type === "delay"
      ? "deliveryDelay"
      : type === "rendering_failure"
      ? "failure"
      : type
  ] ?? {};
  const time = detail.timestamp ?? root.mail.timestamp;
  if (!Number.isFinite(Date.parse(time))) throw new Error("invalid_ses_time");
  const recipients = type === "bounce"
    ? detail.bouncedRecipients
    : type === "complaint"
    ? detail.complainedRecipients
    : root.mail.destination;
  if (!Array.isArray(recipients) || !recipients.length) {
    throw new Error("invalid_ses_recipients");
  }
  const attempt = root.mail.tags?.attempt_id?.[0];
  return recipients.map((r: any) => {
    const recipient = typeof r === "string" ? r : r.emailAddress;
    if (typeof recipient !== "string" || !recipient.includes("@")) {
      throw new Error("invalid_ses_recipient");
    }
    return {
      key: JSON.stringify([
        topic,
        root.mail.messageId,
        recipient.toLowerCase(),
        type,
        time,
      ]),
      provider_id: root.mail.messageId,
      attempt_id:
        typeof attempt === "string" && /^[0-9a-f-]{36}$/i.test(attempt)
          ? attempt
          : null,
      recipient: recipient.toLowerCase(),
      type,
      time,
      hard_bounce: type === "bounce" && detail.bounceType === "Permanent",
      invalid_recipient: type === "bounce" &&
        detail.bounceType === "Permanent" &&
        typeof r === "object" &&
        ["5.1.1", "5.1.2", "5.1.3", "5.1.6"].includes(r.status),
    };
  });
  // No IP, UA, click URL/query or raw payload persists.
}
