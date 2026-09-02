import { X509Certificate, verify } from "node:crypto";

export class SnsVerificationError extends Error {}

type SnsEnvelope = Record<string, unknown>;

function requiredString(message: SnsEnvelope, key: string): string {
  const value = message[key];
  if (typeof value !== "string" || !value) throw new SnsVerificationError(`missing_${key}`);
  return value;
}

function topicRegion(topicArn: string): string {
  const match = topicArn.match(/^arn:aws:sns:([a-z0-9-]+):\d{12}:[A-Za-z0-9_-]+$/);
  if (!match) throw new SnsVerificationError("invalid_topic");
  return match[1];
}

export function trustedSnsUrl(value: unknown, expectedTopicArn: string, confirmation = false): URL {
  if (typeof value !== "string") throw new SnsVerificationError("invalid_sns_url");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new SnsVerificationError("invalid_sns_url");
  }
  const expectedHost = `sns.${topicRegion(expectedTopicArn)}.amazonaws.com`;
  if (url.protocol !== "https:" || url.hostname !== expectedHost || url.port ||
      url.username || url.password || url.hash) {
    throw new SnsVerificationError("untrusted_sns_url");
  }
  if (confirmation) {
    if (url.pathname !== "/" || url.searchParams.get("Action") !== "ConfirmSubscription" ||
        url.searchParams.get("TopicArn") !== expectedTopicArn || !url.searchParams.get("Token")) {
      throw new SnsVerificationError("invalid_confirmation_url");
    }
  } else if (!/^\/SimpleNotificationService-[A-Za-z0-9]+\.pem$/.test(url.pathname) || url.search) {
    throw new SnsVerificationError("invalid_certificate_url");
  }
  return url;
}

export function canonicalSnsString(message: SnsEnvelope): string {
  const type = requiredString(message, "Type");
  const fields = type === "Notification"
    ? ["Message", "MessageId", ...(message.Subject === undefined ? [] : ["Subject"]), "Timestamp", "TopicArn", "Type"]
    : type === "SubscriptionConfirmation"
    ? ["Message", "MessageId", "SubscribeURL", "Timestamp", "Token", "TopicArn", "Type"]
    : [];
  if (fields.length === 0) throw new SnsVerificationError("unsupported_type");
  return fields.map((field) => `${field}\n${requiredString(message, field)}\n`).join("");
}

async function defaultCertificate(url: URL): Promise<string> {
  const response = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new SnsVerificationError("certificate_unavailable");
  const declared = Number(response.headers.get("content-length") ?? 0);
  if (declared > 16 * 1024) throw new SnsVerificationError("certificate_too_large");
  const pem = await response.text();
  if (pem.length > 16 * 1024 || !pem.includes("BEGIN CERTIFICATE")) {
    throw new SnsVerificationError("invalid_certificate");
  }
  return pem;
}

export async function verifySnsEnvelope(
  message: SnsEnvelope,
  headers: Headers,
  expectedTopicArn: string,
  dependencies = { certificate: defaultCertificate },
) {
  if (requiredString(message, "TopicArn") !== expectedTopicArn ||
      requiredString(message, "SignatureVersion") !== "2") {
    throw new SnsVerificationError("topic_or_signature_version_mismatch");
  }
  for (const [header, field] of [
    ["x-amz-sns-message-type", "Type"],
    ["x-amz-sns-message-id", "MessageId"],
    ["x-amz-sns-topic-arn", "TopicArn"],
  ]) {
    if (headers.get(header) !== requiredString(message, field)) {
      throw new SnsVerificationError("header_mismatch");
    }
  }
  const certificateUrl = trustedSnsUrl(message.SigningCertURL, expectedTopicArn);
  if (message.Type === "SubscriptionConfirmation") {
    trustedSnsUrl(message.SubscribeURL, expectedTopicArn, true);
  }
  const certificate = new X509Certificate(await dependencies.certificate(certificateUrl));
  const signature = Uint8Array.from(atob(requiredString(message, "Signature")), (value) => value.charCodeAt(0));
  if (!verify("RSA-SHA256", new TextEncoder().encode(canonicalSnsString(message)), certificate.publicKey, signature)) {
    throw new SnsVerificationError("invalid_signature");
  }
}
