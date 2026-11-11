import type { Tone } from "./communicationTone.ts";
import { escapeEmailHtml } from "./emailActionLink.ts";

export function resolveEmailLanguage(value: unknown): "cs" | "en" {
  return value === "en" ? "en" : "cs";
}

export function orderIdentityValues(
  occasionTitle: string,
  orderSymbol: string,
) {
  if (typeof orderSymbol !== "string" || !orderSymbol.trim()) {
    throw new Error("order_email_identity_missing");
  }
  return { occasionTitle, orderSymbol };
}

export function orderTemplateValues(
  code: string,
  title: string,
  symbol: string,
  tone: Tone,
  language: unknown = "cs",
) {
  return {
    ...orderIdentityValues(title, symbol),
    orderCommunication: orderCommunication(code, title, tone, language),
  };
}

/** Tone-aware introduction shared by delivery and every order preview. */
export function orderCommunication(
  templateCode: string,
  title: string,
  tone: Tone,
  language: unknown = "cs",
): string {
  const name = escapeEmailHtml(title);
  const informal = tone === "informal";
  const english = resolveEmailLanguage(language) === "en";
  const greeting = english ? "Hello" : informal ? "Ahoj" : "Dobrý den";
  switch (templateCode) {
    case "TICKET_ORDER_CONFIRMATION":
      return `<p>${greeting}, ${
        english
          ? "we confirm your registration for"
          : `potvrzujeme ${informal ? "Tvou" : "Vaši"} registraci na akci`
      } <strong>${name}</strong>.</p>`;
    case "TICKET_ORDER_UPDATE":
      return `<p>${greeting},</p><p>${
        english
          ? `Your order for ${name} has been updated.`
          : `${
            informal ? "Tvá" : "Vaše"
          } objednávka na akci ${name} byla změněna.`
      }</p>`;
    case "TICKET_ORDER_PAYMENT_DONE":
      return english
        ? `<h3>Your payment for ${name} has arrived</h3><p>${greeting},<br>we confirm receipt of payment for your registration for ${name}.</p>`
        : `<h3>${
          informal ? "Tvá" : "Vaše"
        } platba na akci ${name} dorazila</h3><p>${greeting},<br>potvrzujeme přijetí platby za ${
          informal ? "Tvou" : "Vaši"
        } registraci na akci ${name}.</p>`;
    case "TICKET_ORDER_STORNO":
      return `<p>${greeting},</p><p>${
        english
          ? `Your order for ${name} has been cancelled.`
          : `${
            informal ? "Tvá" : "Vaše"
          } objednávka na akci ${name} byla stornována.`
      }</p>`;
    case "TICKET_ORDER_REMINDER":
      return `<p>${greeting},</p>`;
    default:
      throw new Error("unsupported_order_communication");
  }
}
