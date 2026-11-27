export interface MetaPurchase {
  dataset: string;
  accessToken: string;
  testEventCode: string | null;
  eventId: string;
  eventTime: number;
  value: number;
  currency: string;
  emailHash: string;
  phoneHash?: string | null;
  fbp?: string | null;
  fbc?: string | null;
  clientIp?: string | null;
  clientAgent: string;
  sourceUrl: string;
}

export type MetaPurchaseResult =
  | "sent"
  | "sent_test_inactive"
  | "retry"
  | "credentials"
  | "rejected";

// Meta accepts events whose test_event_code has no active Test Events session
// but reports that they will not appear there.
const inactiveTestSession = /does not match an active Test Events session/i;

export async function sendMetaPurchase(
  purchase: MetaPurchase,
  send: typeof fetch = fetch,
): Promise<MetaPurchaseResult> {
  if (!/^\d{5,30}$/.test(purchase.dataset)) return "rejected";
  try {
    const response = await send(
      `https://graph.facebook.com/v25.0/${purchase.dataset}/events`,
      {
        method: "POST",
        redirect: "error",
        headers: {
          Authorization: `Bearer ${purchase.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          data: [{
            event_name: "Purchase",
            event_id: purchase.eventId,
            event_time: purchase.eventTime,
            action_source: "website",
            event_source_url: purchase.sourceUrl,
            user_data: {
              em: [purchase.emailHash],
              client_user_agent: purchase.clientAgent,
              ...(purchase.phoneHash ? { ph: [purchase.phoneHash] } : {}),
              ...(purchase.fbp ? { fbp: purchase.fbp } : {}),
              ...(purchase.fbc ? { fbc: purchase.fbc } : {}),
              ...(purchase.clientIp
                ? { client_ip_address: purchase.clientIp }
                : {}),
            },
            custom_data: { value: purchase.value, currency: purchase.currency },
          }],
          ...(purchase.testEventCode
            ? { test_event_code: purchase.testEventCode }
            : {}),
        }),
        signal: AbortSignal.timeout(8000),
      },
    );
    const receipt = await response.json().catch(() => null);
    if (response.ok) {
      if (receipt?.events_received !== 1) return "retry";
      const messages: unknown[] = Array.isArray(receipt?.messages)
        ? receipt.messages
        : [];
      return purchase.testEventCode &&
          messages.some((message) =>
            typeof message === "string" && inactiveTestSession.test(message)
          )
        ? "sent_test_inactive"
        : "sent";
    }
    const code = receipt?.error?.code;
    // Graph throttling (#4, #17, #32, #613, 80000-80014) can arrive as 400 or
    // 403. It must not pause the connector or discard the purchase.
    if (
      receipt?.error?.is_transient === true ||
      [1, 2, 4, 17, 32, 613].includes(code) ||
      (code >= 80000 && code <= 80014) ||
      response.status === 429 || response.status >= 500
    ) return "retry";
    if (
      response.status === 401 || response.status === 403 ||
      [10, 102, 190].includes(code) || (code >= 200 && code <= 299)
    ) return "credentials";
    return "rejected";
  } catch {
    return "retry";
  }
}
