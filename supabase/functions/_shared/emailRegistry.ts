export const emailRegistry = {
  order_confirmation: { code: "TICKET_ORDER_CONFIRMATION", sensitive: false },
  order_payment_notice: { code: "TICKET_ORDER_PAYMENT_DONE", sensitive: false },
  order_tickets: { code: "TICKET_ORDER_PAYMENT_DONE", sensitive: false },
  order_reminder: { code: "TICKET_ORDER_REMINDER", sensitive: false },
  order_update: { code: "TICKET_ORDER_UPDATE", sensitive: false },
  order_storno: { code: "TICKET_ORDER_STORNO", sensitive: false },
  registration: { code: "REGISTER", sensitive: true },
  sign_in: { code: "SIGN_IN_CODE", sensitive: true },
  reset_password: { code: "RESET_PASSWORD", sensitive: true },
  app_links: { code: "APP_LINKS", sensitive: false },
  deletion_confirm: { code: "ACCOUNT_DELETION_CONFIRM", sensitive: true },
  deletion_complete: { code: "ACCOUNT_DELETION_COMPLETE", sensitive: true },
  google_mailbox: { code: "", sensitive: true },
  gotrue: { code: "", sensitive: true },
  custom: { code: "", sensitive: false },
} as const;
export type EmailKind = keyof typeof emailRegistry;
export function kindForTemplate(code: string): EmailKind {
  const match = Object.entries(emailRegistry).find(([kind, spec]) =>
    spec.code === code && !kind.startsWith("order_")
  );
  return (match?.[0] ?? "custom") as EmailKind;
}
