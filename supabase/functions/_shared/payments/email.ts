import { PaymentError, type PaymentSecrets, record } from "./contracts.ts";
const escape = (value: unknown) =>
  String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(
    ">",
    "&gt;",
  ).replaceAll('"', "&quot;").replaceAll("'", "&#39;");
export function paymentConfirmationBalance(
  source: unknown,
  secrets: PaymentSecrets | undefined,
  language: string,
  amount: string,
  deadline: string,
  policy: {
    providerId: string;
    providerName: string;
    payPath: string;
    allowedOrigins: readonly string[];
  },
) {
  const value = record(source), payment = record(value.payment);
  const cs = language === "cs";
  if (payment.method !== policy.providerId) {
    throw new PaymentError("payment_email_source_invalid");
  }
  const copy: Record<string, string> = cs
    ? {
      paid: "Platba byla přijata. Vstupenky posíláme samostatně.",
      partially_refunded: "Část platby byla vrácena. Nevzniká tím nová platba.",
      refunded:
        "Platba byla vrácena. Tato zpráva nepotvrzuje platnost vstupenek.",
      disputed:
        "Platba je ve sporu. Vstupenky vyžadují ověření pořadatelem. Znovu neplaťte.",
      action_required: "Platbu musí vyřešit pořadatel. Znovu neplaťte.",
      expired: "Čas na dokončení objednávky vypršel. Novou platbu nezahajujte.",
    }
    : {
      paid: "Payment received. Tickets are sent separately.",
      partially_refunded:
        "Part of the payment was refunded. This does not create another payment.",
      refunded:
        "The payment was refunded. This message does not confirm ticket validity.",
      disputed:
        "The payment is disputed. The organizer must verify admission. Do not pay again.",
      action_required:
        "The organizer must resolve this payment. Do not pay again.",
      expired: "The reservation has expired. Do not start another payment.",
    };
  if (payment.status !== "open" && payment.status !== "preparing") {
    return `<p>${
      escape(
        copy[String(payment.status)] ?? (cs
          ? "Stav platby nelze ověřit. Znovu neplaťte."
          : "Payment status cannot be verified. Do not pay again."),
      )
    }</p>`;
  }
  const url = new URL(String(value.payBaseUrl));
  if (
    url.protocol !== "https:" || url.username || url.password || url.search ||
    url.hash || !policy.allowedOrigins.includes(url.origin) ||
    !url.pathname.endsWith(policy.payPath) ||
    !/^[a-f0-9]{64}$/.test(secrets?.payToken ?? "")
  ) throw new PaymentError("payment_email_origin_invalid");
  url.hash = "pay=" + secrets!.payToken;
  return `<p>${
    cs
      ? "Objednávka čeká na platbu. Částka k úhradě:"
      : "Your order awaits payment. Amount due:"
  } <strong>${escape(amount)}</strong>. ${
    cs ? "Platnost rezervace do" : "Reservation valid until"
  } ${escape(deadline)}.</p><p><a href="${escape(url.toString())}">${
    cs ? "Pokračovat v platbě" : "Continue payment"
  }</a></p><p>${
    cs
      ? `Zaplatíte bezpečně přes ${
        escape(policy.providerName)
      }. Vstupenky obdržíte po potvrzení platby.`
      : `Pay securely through ${
        escape(policy.providerName)
      }. Tickets are issued after payment confirmation.`
  }</p>`;
}
