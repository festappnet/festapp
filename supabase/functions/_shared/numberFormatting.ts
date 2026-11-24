/** Display policy shared by web, emails and PDFs. Never use for wire values. */
export const numberGroupingThreshold = 10_000;

export function formatDisplayNumber(
  value: number,
  locale: string = 'cs-CZ',
  options: Intl.NumberFormatOptions = {},
): string {
  return new Intl.NumberFormat(locale, {
    ...options,
    useGrouping: Math.abs(value) >= numberGroupingThreshold,
  }).format(value);
}

// Ticket display can override the currency's ISO fraction digits without
// changing the precision of prices used by checkout or payment processing.
const ticketCurrencyFractionDigits: Readonly<Record<string, number>> = { CZK: 0 };

export function formatTicketCurrency(value: number, currency: string, locale = 'cs-CZ'): string {
  currency = currency.toUpperCase();
  const digits = ticketCurrencyFractionDigits[currency];
  return formatDisplayNumber(value, locale, {
    style: 'currency',
    currency,
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}
