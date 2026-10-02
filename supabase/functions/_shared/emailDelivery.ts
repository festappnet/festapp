import nodemailer from "npm:nodemailer@6.9.16";

const _SMTP_HOSTNAME = Deno.env.get("SMTP_HOSTNAME") || "";
const _SMTP_USER_NAME = Deno.env.get("SMTP_USER_NAME") || "";
const _SMTP_USER_PASSWORD = Deno.env.get("SMTP_USER_PASSWORD") || "";
const _DEFAULT_EMAIL = Deno.env.get("DEFAULT_EMAIL") || "";
const _SMTP_PORT = Number(Deno.env.get("SMTP_PORT") || "465");
const _SMTP_SECURE = (Deno.env.get("SMTP_SECURE") || "true") === "true";

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
};

export type EmailDeliveryResult = {
  templateId: string | number | null;
  logged: boolean;
};

type EmailLog = {
  from: string;
  to: string;
  template: string | number | null;
  organization: number;
  occasion?: number | null;
  unit?: number | null;
  recipient_user?: string | null;
};

export type EmailDeliveryDependencies = {
  resolveTemplateAndWrapper(
    templateCode: string,
    context: EmailContext,
  ): Promise<ResolvedEmail>;
  sendMail(message: Record<string, unknown>): Promise<unknown>;
  logEmail(entry: EmailLog): Promise<void>;
};

export class EmailTemplateNotFoundError extends Error {
  constructor(templateCode: string) {
    super(`Template not found for code ${templateCode}`);
    this.name = "EmailTemplateNotFoundError";
  }
}

export class EmailDeliveryError extends Error {
  constructor(cause: unknown) {
    super("Email transport failed", { cause });
    this.name = "EmailDeliveryError";
  }
}

const transporter = nodemailer.createTransport({
  host: _SMTP_HOSTNAME,
  port: _SMTP_PORT,
  secure: _SMTP_SECURE,
  ...(_SMTP_USER_NAME && _SMTP_USER_PASSWORD
    ? { auth: { user: _SMTP_USER_NAME, pass: _SMTP_USER_PASSWORD } }
    : {}),
});

const defaultDependencies: EmailDeliveryDependencies = {
  async resolveTemplateAndWrapper(templateCode, context) {
    const { getEmailTemplateAndWrapper } = await import("./supabaseUtil.ts");
    return await getEmailTemplateAndWrapper(templateCode, context);
  },
  sendMail: (message) => transporter.sendMail(message),
  async logEmail(entry) {
    const { supabaseAdmin } = await import("./supabaseUtil.ts");
    const { error } = await supabaseAdmin.from("log_emails").insert(entry);
    if (error) throw error;
  },
};

function substitute(value: string, substitutions: Record<string, unknown>) {
  let result = value;
  for (const [key, replacement] of Object.entries(substitutions)) {
    result = result.replaceAll(`{{${key}}}`, String(replacement));
  }
  return result;
}

export function createEmailDelivery(
  dependencies: EmailDeliveryDependencies,
) {
  return async function deliverEmail(
    {
      to,
      recipientUser,
      templateCode = "",
      context,
      substitutions,
      attachments = [],
      from = _DEFAULT_EMAIL,
      replyTo = _DEFAULT_EMAIL,
      messageId,
      template: templateOverride,
    }: DeliverEmailInput,
  ): Promise<EmailDeliveryResult> {
    const resolved = await dependencies.resolveTemplateAndWrapper(
      templateCode,
      context,
    );
    const template = templateOverride ?? resolved?.template;

    if (
      !template || typeof template.subject !== "string" ||
      typeof template.html !== "string"
    ) {
      throw new EmailTemplateNotFoundError(templateCode || "<inline>");
    }

    const subject = substitute(template.subject, substitutions);
    let html = substitute(template.html, substitutions);
    const wrapper = resolved?.wrapper?.html;
    if (wrapper) html = wrapper.replace("{{content}}", html);

    try {
      await dependencies.sendMail({
        from,
        to,
        subject,
        // Template links and layout are authoritative. Send the assembled HTML
        // without automatic link detection or whitespace postprocessing.
        html,
        replyTo,
        ...(messageId ? { messageId } : {}),
        attachments: attachments.map((attachment) => ({
          filename: attachment.filename,
          content: attachment.content,
          contentType: attachment.contentType,
          encoding: attachment.encoding,
        })),
      });
    } catch (error) {
      console.error("Email transport failed");
      throw new EmailDeliveryError(error);
    }

    let logged = true;
    try {
      await dependencies.logEmail({
        from: _DEFAULT_EMAIL,
        to,
        template: template.id,
        organization: context.organization,
        occasion: context.occasion,
        unit: context.unit,
        recipient_user: recipientUser,
      });
    } catch (error) {
      // The email is already accepted by SMTP. Failing the request here could
      // cause a retry and duplicate delivery, so evidence failure is reported
      // separately without turning a successful delivery into an error.
      logged = false;
      console.error("Email accepted, but delivery evidence logging failed");
    }

    return { templateId: template.id, logged };
  };
}

export const deliverEmail = createEmailDelivery(defaultDependencies);
