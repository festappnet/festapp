type RpcError = { code?: string; message?: string; details?: string };
type RpcClient = {
  rpc(name: string, parameters: Record<string, unknown>): PromiseLike<{
    data: unknown;
    error: RpcError | null;
  }>;
};

/** Preserve definitive admission rejections across both authorization paths. */
export async function executeTicketOrderRpc(
  client: RpcClient,
  name: string,
  parameters: Record<string, unknown>,
) {
  const { data, error } = await client.rpc(name, parameters);
  if (!error) {
    const order = data !== null && typeof data === "object" && "data" in data
      ? data.data ?? data
      : data;
    return { envelope: data, order, error: null };
  }
  if (error.code !== "PT429") {
    return {
      envelope: null,
      order: { code: 500, message: error.message },
      error,
    };
  }
  let details: { ruleKey?: string; retryAfterSeconds?: number } = {};
  try {
    details = JSON.parse(error.details ?? "{}");
  } catch { /* No public detail is required for a known rejection. */ }
  const rule = typeof details?.ruleKey === "string" ? details.ruleKey : "";
  const retry = details?.retryAfterSeconds;
  return {
    envelope: null,
    error,
    order: {
      code: 429,
      errorCode: "ABUSE_LIMIT_EXCEEDED",
      limitReason: rule.startsWith("email.")
        ? rule.includes(".recipient.") ? "email_recipient" : "email_service"
        : "service",
      ...(Number.isSafeInteger(retry) && retry! > 0 && retry! <= 604800
        ? { retryAfterSeconds: retry }
        : {}),
    },
  };
}
