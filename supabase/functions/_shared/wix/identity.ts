export class WixIdentityError extends Error {
  constructor(public readonly code: string, public readonly status = 401) {
    super(code);
  }
}
const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function epoch(value: unknown): number {
  const number = typeof value === "string" && /^\d{1,12}$/.test(value)
    ? Number(value)
    : value;
  if (
    typeof number !== "number" || !Number.isSafeInteger(number) || number <= 0
  ) {
    throw new WixIdentityError("INVALID_WIX_IDENTITY");
  }
  return number;
}

/** Verify with Wix, never decode an unverified JWT or trust browser instance IDs.
 * This identity establishes provenance only, not Festapp resource permission.
 */
export async function verifyWixIdentity(
  authorization: string | null,
  expectedApp: string,
  fetcher: typeof fetch = fetch,
  now = Math.floor(Date.now() / 1000),
): Promise<{ instanceId: string; siteId: string; expiresAt: number }> {
  if (!guid.test(expectedApp)) {
    throw new WixIdentityError("WIX_NOT_CONFIGURED", 503);
  }
  const token = authorization?.replace(/^Bearer /i, "") ?? "";
  if (!token || token.length > 16384 || /[^\x21-\x7e]/.test(token)) {
    throw new WixIdentityError("WIX_AUTHENTICATION_REQUIRED");
  }
  let response: Response;
  try {
    response = await fetcher("https://www.wixapis.com/oauth2/token-info", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
      redirect: "error",
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    throw new WixIdentityError("WIX_VERIFICATION_UNAVAILABLE", 503);
  }
  if (!response.ok) {
    throw new WixIdentityError(
      response.status >= 500 || response.status === 429
        ? "WIX_VERIFICATION_UNAVAILABLE"
        : "INVALID_WIX_IDENTITY",
      response.status >= 500 || response.status === 429 ? 503 : 401,
    );
  }
  let data: Record<string, unknown>;
  try {
    const text = await response.text();
    if (text.length > 32768) throw new Error();
    data = JSON.parse(text);
  } catch {
    throw new WixIdentityError("WIX_VERIFICATION_UNAVAILABLE", 503);
  }
  if (
    !data || Array.isArray(data) ||
    (data.active !== true && data.active !== "true") ||
    typeof data.clientId !== "string" ||
    data.clientId.toLowerCase() !== expectedApp.toLowerCase() ||
    typeof data.instanceId !== "string" || !guid.test(data.instanceId) ||
    typeof data.siteId !== "string" || !guid.test(data.siteId) ||
    !["APP", "USER", "MEMBER", "VISITOR"].includes(String(data.subjectType)) ||
    epoch(data.exp) <= now || epoch(data.iat) > now + 60 ||
    epoch(data.iat) >= epoch(data.exp)
  ) {
    throw new WixIdentityError("INVALID_WIX_IDENTITY");
  }
  return {
    instanceId: data.instanceId.toLowerCase(),
    siteId: data.siteId.toLowerCase(),
    expiresAt: epoch(data.exp),
  };
}
