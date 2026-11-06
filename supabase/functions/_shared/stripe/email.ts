/** Existing renderer imports retain their external name, using the common renderer. */
import { paymentConfirmationBalance } from "../payments/email.ts";
import type { PaymentSecrets } from "../payments/contracts.ts";
export function stripeConfirmationBalance(
  source: unknown,
  secrets: PaymentSecrets | undefined,
  language: string,
  amount: string,
  deadline: string,
  allowedOrigins: string[],
) {
  return paymentConfirmationBalance(
    source,
    secrets,
    language,
    amount,
    deadline,
    {
      providerId: "stripe",
      providerName: "Stripe",
      payPath: "/stripe/pay",
      allowedOrigins,
    },
  );
}
