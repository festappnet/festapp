const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL") || "";
export type EmailContext = {
  organization: number;
  occasion?: number | null;
  unit?: number | null;
  [key: string]: unknown;
};

export type EmailAttachment = {
  filename: string;
  content: unknown;
  contentType: string;
  encoding: string;
  disposition?: "ATTACHMENT" | "INLINE";
  contentId?: string;
};

export type EmailTemplate = {
  id: string | number | null;
  code?: string | null;
  subject: string;
  html: string;
};

type EmailWrapper = {
  html?: string | null;
};

type ResolvedEmail = {
  template?: EmailTemplate | null;
  wrapper?: EmailWrapper | null;
};

export type DeliverEmailInput = {
  to: string;
  /** Auth/user_info recipient when the message concerns one concrete account. */
  recipientUser?: string;
  templateCode?: string;
  context: EmailContext;
  substitutions: Record<string, unknown>;
  subjectSubstitutions?: Record<string, unknown>;
  attachments?: EmailAttachment[];
  from?: string;
  replyTo?: string;
  /** Stable RFC Message-ID used by durable workers across delivery retries. */
  messageId?: string;
  /**
   * Preserves editor-provided template snapshots while the wrapper is still
   * resolved centrally from templateCode and context.
   */
  template?: EmailTemplate;
  /** Trusted system block, composed once before the inherited wrapper. */
  ticketBlock?: string;
};

export type EmailDeliveryResult = {
  templateId: string | number | null;
  logged: boolean;
};

export class EmailTemplateNotFoundError extends Error {
  constructor(templateCode: string) {
    super(`Template not found for code ${templateCode}`);
    this.name = "EmailTemplateNotFoundError";
  }
}

function substitute(value: string, substitutions: Record<string, unknown>) {
  let result = value;
  for (const [key, replacement] of Object.entries(substitutions)) {
    result = result.replaceAll(`{{${key}}}`, String(replacement));
  }
  return result;
}

export type PreparedEmail = {
  from: string;
  to: string;
  subject: string;
  html: string;
  replyTo: string;
  attachments: Array<
    {
      filename: string;
      content: string;
      contentType: string;
      encoding: "base64";
      disposition?: "ATTACHMENT" | "INLINE";
      contentId?: string;
    }
  >;
};
export function encodeAttachment(content: unknown, encoding: string): string {
  if (encoding === "base64" && typeof content === "string") return content;
  const bytes = content instanceof Uint8Array
    ? content
    : typeof content === "string"
    ? new TextEncoder().encode(content)
    : null;
  if (!bytes) throw new Error("invalid_email_attachment");
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(binary);
}
export async function renderEmail(
  input: DeliverEmailInput,
  resolver?: (code: string, context: EmailContext) => Promise<ResolvedEmail>,
): Promise<PreparedEmail> {
  if (!resolver) {
    const { getEmailTemplateAndWrapper } = await import("./supabaseUtil.ts");
    resolver = getEmailTemplateAndWrapper;
  }
  const resolved = await resolver(input.templateCode ?? "", input.context);
  const template = input.template ?? resolved?.template;
  if (
    !template || typeof template.subject !== "string" ||
    typeof template.html !== "string"
  ) throw new EmailTemplateNotFoundError(input.templateCode ?? "inline");
  const subject = substitute(
    template.subject,
    input.subjectSubstitutions ?? input.substitutions,
  );
  let body = template.html;
  const ticketBlock = input.ticketBlock ??
    (input.templateCode === "TICKET_ORDER_PAYMENT_DONE" ? "" : undefined);
  if (ticketBlock !== undefined) {
    const marker = "{{tickets}}";
    const first = body.indexOf(marker);
    body = first < 0 ? body + ticketBlock : body.slice(0, first) + ticketBlock +
      body.slice(first + marker.length).replaceAll(marker, "");
  }
  let html = substitute(body, input.substitutions);
  if (resolved?.wrapper?.html) {
    html = resolved.wrapper.html.replace("{{content}}", html);
  }
  return {
    from: input.from ?? _DEFAULT_EMAIL,
    to: input.to,
    subject,
    html,
    replyTo: input.replyTo ?? _DEFAULT_EMAIL,
    attachments: (input.attachments ?? []).map((a) => ({
      filename: a.filename,
      content: encodeAttachment(a.content, a.encoding),
      contentType: a.contentType,
      encoding: "base64",
      ...(a.disposition ? { disposition: a.disposition } : {}),
      ...(a.contentId ? { contentId: a.contentId } : {}),
    })),
  };
}
