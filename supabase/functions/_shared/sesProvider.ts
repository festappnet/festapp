// This module is imported only by the isolated gateway, never by producers/worker.
import type { PreparedEmail } from "./emailDelivery.ts";
export type SesConfig = {
  region: string;
  accessKey: string;
  secretKey: string;
  sessionToken?: string;
  sender: string;
  transactionalSet: string;
  securitySet: string;
  engagementSet?: string;
  maxBytes: number;
};
export class SesFailure extends Error {
  constructor(
    public outcome: "retry" | "dead" | "unknown",
    public code: string,
  ) {
    super(code);
  }
}
function hex(bytes: ArrayBuffer) {
  return Array.from(
    new Uint8Array(bytes),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
async function sha(value: string) {
  return hex(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}
async function hmac(key: Uint8Array<ArrayBuffer>, value: string) {
  const k = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(
    await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(value)),
  );
}
export function sesBody(
  message: PreparedEmail,
  config: SesConfig,
  tags: Record<string, string>,
  sensitive: boolean,
  engagement = false,
) {
  if (engagement && !config.engagementSet) {
    throw new SesFailure("dead", "engagement_set_missing");
  }
  const address = message.from.match(/<([^<>]+)>$/)?.[1] ?? message.from;
  if (
    address !== config.sender ||
    /[\r\n]/.test(message.from + message.replyTo + message.subject)
  ) throw new SesFailure("dead", "invalid_sender");
  const size = new TextEncoder().encode(message.html + message.subject).length +
    message.attachments.reduce((sum, a) => sum + a.content.length + 1024, 0);
  if (size > Math.min(config.maxBytes, 40_000_000) - 4096) {
    throw new SesFailure("dead", "message_too_large");
  }
  return {
    FromEmailAddress: message.from,
    ReplyToAddresses: [message.replyTo],
    Destination: { ToAddresses: [message.to] },
    ConfigurationSetName: sensitive
      ? config.securitySet
      : engagement
      ? config.engagementSet
      : config.transactionalSet,
    EmailTags: Object.entries(tags).map(([Name, Value]) => ({ Name, Value })),
    Content: {
      Simple: {
        Subject: { Data: message.subject, Charset: "UTF-8" },
        Body: { Html: { Data: message.html, Charset: "UTF-8" } },
        Attachments: message.attachments.map((a) => ({
          FileName: a.filename,
          ContentType: a.contentType,
          RawContent: a.content,
          ContentDisposition: "ATTACHMENT",
          ContentTransferEncoding: "BASE64",
        })),
      },
    },
  };
}
export async function sesRequest(
  config: SesConfig,
  method: "GET" | "POST",
  path: string,
  payload: unknown,
  sendFetch: typeof fetch = fetch,
  identity = false,
): Promise<Record<string, any>> {
  if (!config.region || !config.accessKey || !config.secretKey) {
    throw new SesFailure("dead", "ses_not_configured");
  }
  const service = identity ? "sts" : "ses";
  const host = identity
      ? `sts.${config.region}.amazonaws.com`
      : `email.${config.region}.amazonaws.com`,
    body = identity
      ? "Action=GetCallerIdentity&Version=2011-06-15"
      : method === "POST"
      ? JSON.stringify(payload)
      : "";
  const amzDate = new Date().toISOString().replace(/[-:]/g, "").replace(
      /\.\d+Z$/,
      "Z",
    ),
    date = amzDate.slice(0, 8);
  const hdr: Record<string, string> = {
    "content-type": identity
      ? "application/x-www-form-urlencoded"
      : "application/json",
    host,
    "x-amz-date": amzDate,
  };
  if (config.sessionToken) hdr["x-amz-security-token"] = config.sessionToken;
  const names = Object.keys(hdr).sort();
  const canonical = names.map((name) => `${name}:${hdr[name]}\n`).join("");
  const scope = `${date}/${config.region}/${service}/aws4_request`;
  const request = [
    method,
    path,
    "",
    canonical,
    names.join(";"),
    await sha(body),
  ].join("\n");
  let key = await hmac(
    new TextEncoder().encode(`AWS4${config.secretKey}`),
    date,
  );
  key = await hmac(key, config.region);
  key = await hmac(key, service);
  key = await hmac(key, "aws4_request");
  hdr.authorization =
    `AWS4-HMAC-SHA256 Credential=${config.accessKey}/${scope}, SignedHeaders=${
      names.join(";")
    }, Signature=${
      hex(
        (await hmac(
          key,
          ["AWS4-HMAC-SHA256", amzDate, scope, await sha(request)].join("\n"),
        )).buffer,
      )
    }`;
  delete hdr.host;
  let res: Response;
  try {
    res = await sendFetch(`https://${host}${path}`, {
      method,
      headers: hdr,
      ...(method === "POST" ? { body } : {}),
      redirect: "error",
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new SesFailure("unknown", "transport_ambiguous");
  }
  let result: Record<string, any> = {};
  try {
    if (identity) {
      const xml = await res.text();
      const account = xml.match(/<Account>([0-9]{12})<\/Account>/)?.[1];
      if (!res.ok || !account) throw new Error("identity_unavailable");
      result = { Account: account };
    } else result = await res.json();
  } catch {
    throw new SesFailure("unknown", "response_ambiguous");
  }
  if (!res.ok) {
    const code = String(
      result.__type ?? result.code ?? res.headers.get("x-amzn-errortype") ?? "",
    ).split("#").at(-1)?.split(":")[0];
    if (res.status === 429 && code === "TooManyRequestsException") {
      throw new SesFailure("retry", "throttled");
    }
    if (
      [
        "AccountSuspendedException",
        "BadRequestException",
        "MailFromDomainNotVerifiedException",
        "MessageRejected",
        "NotFoundException",
        "SendingPausedException",
      ].includes(code ?? "")
    ) throw new SesFailure("dead", code!);
    throw new SesFailure("unknown", "provider_ambiguous");
  }
  return result;
}
export async function sendSes(
  message: PreparedEmail,
  config: SesConfig,
  tags: Record<string, string>,
  sensitive: boolean,
  sendFetch: typeof fetch = fetch,
  engagement = false,
) {
  const result = await sesRequest(
    config,
    "POST",
    "/v2/email/outbound-emails",
    sesBody(message, config, tags, sensitive, engagement),
    sendFetch,
  );
  if (typeof result.MessageId !== "string" || !result.MessageId) {
    throw new SesFailure("unknown", "message_id_missing");
  }
  return result.MessageId;
}

export async function verifySesAccount(
  config: SesConfig,
  expected: string,
  sendFetch: typeof fetch = fetch,
) {
  if (!/^[0-9]{12}$/.test(expected)) {
    throw new SesFailure("dead", "account_identity_not_configured");
  }
  const identity = await sesRequest(config, "POST", "/", null, sendFetch, true);
  if (identity.Account !== expected) {
    throw new SesFailure("dead", "account_identity_mismatch");
  }
  return identity.Account as string;
}

/** Validate actual provider destinations before accepting a fresh sending quota. */
export async function verifySesConfiguration(
  config: SesConfig,
  topicArn: string,
  sendFetch: typeof fetch = fetch,
) {
  if (!/^arn:aws:sns:[a-z0-9-]+:\d{12}:[A-Za-z0-9_-]+$/.test(topicArn)) {
    throw new SesFailure("dead", "feedback_topic_not_configured");
  }
  const required = [
    "SEND",
    "DELIVERY",
    "BOUNCE",
    "COMPLAINT",
    "REJECT",
    "RENDERING_FAILURE",
    "DELIVERY_DELAY",
  ];
  const sets: Array<[string, string]> = [[config.securitySet, "disabled"], [
    config.transactionalSet,
    "open",
  ]];
  if (config.engagementSet) sets.push([config.engagementSet, "engagement"]);
  for (const [name, policy] of sets) {
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(name)) {
      throw new SesFailure("dead", "configuration_set_missing");
    }
    const response = await sesRequest(
      config,
      "GET",
      `/v2/email/configuration-sets/${name}/event-destinations`,
      null,
      sendFetch,
    );
    const enabled = (response.EventDestinations ?? []).filter((d: any) =>
      d.Enabled === true
    );
    const all = enabled.flatMap((d: any) => d.MatchingEventTypes ?? []);
    if (
      (policy === "disabled" &&
        (all.includes("OPEN") || all.includes("CLICK"))) ||
      (policy === "open" && all.includes("CLICK"))
    ) throw new SesFailure("dead", "unsafe_tracking_configuration");
    const routed = enabled.filter((d: any) =>
      d.SnsDestination?.TopicArn === topicArn
    ).flatMap((d: any) => d.MatchingEventTypes ?? []);
    if (
      !required.every((type) => routed.includes(type)) ||
      (policy !== "disabled" && !routed.includes("OPEN")) ||
      (policy === "engagement" && !routed.includes("CLICK"))
    ) throw new SesFailure("dead", "feedback_destination_missing");
  }
  const address = config.sender.match(/<([^<>]+)>$/)?.[1] ?? config.sender;
  const identities = [address, address.split("@")[1]].filter(Boolean);
  for (const identity of identities) {
    try {
      const response = await sesRequest(
        config,
        "GET",
        `/v2/email/identities/${encodeURIComponent(identity)}`,
        null,
        sendFetch,
      );
      if (response.VerifiedForSendingStatus === true) return;
    } catch (e) {
      if (!(e instanceof SesFailure) || e.code !== "NotFoundException") throw e;
    }
  }
  throw new SesFailure("dead", "sender_identity_not_verified");
}
