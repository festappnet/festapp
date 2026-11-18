export interface MetaPurchase {
  dataset: string;
  accessToken: string;
  testEventCode: string | null;
  eventId: string;
  eventTime: number;
  value: number;
  currency: string;
  emailHash: string;
  clientAgent: string;
  sourceUrl: string;
}

export type MetaPurchaseResult = "sent" | "retry" | "credentials" | "rejected";

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
    if (response.ok) return receipt?.events_received === 1 ? "sent" : "retry";
    if (
      response.status === 401 || response.status === 403 ||
      [10, 190, 200].includes(receipt?.error?.code)
    ) return "credentials";
    if (
      response.status === 429 || response.status >= 500 ||
      receipt?.error?.is_transient === true
    ) return "retry";
    return "rejected";
  } catch {
    return "retry";
  }
}
