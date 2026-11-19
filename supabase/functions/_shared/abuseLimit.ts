/** Public, bounded projection of a canonical admission rejection. */
export function abuseLimitDetails(value?: string) {
  let details: { ruleKey?: string; retryAfterSeconds?: number } = {};
  try {
    details = JSON.parse(value ?? "{}");
  } catch { /* No public detail is required for a known rejection. */ }
  const rule = typeof details?.ruleKey === "string" ? details.ruleKey : "";
  const retry = details?.retryAfterSeconds;
  return {
    code: 429,
    errorCode: "ABUSE_LIMIT_EXCEEDED",
    limitReason: rule.startsWith("email.")
      ? rule.includes(".recipient.") ? "email_recipient" : "email_service"
      : "service",
    ...(Number.isSafeInteger(retry) && retry! > 0 && retry! <= 604800
      ? { retryAfterSeconds: retry }
      : {}),
  };
}
