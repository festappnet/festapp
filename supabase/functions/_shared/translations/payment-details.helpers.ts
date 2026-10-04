// Helper function to wrap text in HTML strong tags for bolding, preventing line breaks.
export const bold = (text: string | number) => `<strong style="white-space: nowrap;">${text}</strong>`;

/**
 * Defines the options for the payment details component.
 */
export interface PaymentDetailsOptions {
  accountNumber: string;
  variableSymbol: string;
  amount: string;
  iban?: string | null;
  note?: string | null;
  lang?: 'cs' | 'en';
}

/**
 * Defines the supported tones for translations.
 */
export type Tone = 'formal' | 'informal';

// Render short text runs so mail clients do not mistake an account for a phone
// number. Tags add no spaces or invisible characters to the copyable value.
const renderAccountNumber = (value: string) => {
  const escaped = value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return `<span class="festapp-payment-account" style="white-space: nowrap; pointer-events: none; cursor: text;">${
    escaped.replace(/\d{1,3}/g, '<span style="display: inline-block;">$&</span>')
  }</span>`;
};

/**
 * Creates a styled, readable block for payment details.
 * The 'note' parameter is now a standard detail row.
 * @param options - The payment details configuration.
 * @returns An HTML string for the payment details block.
 */
export const generatePaymentDetails = (options: PaymentDetailsOptions) => {
  const { accountNumber, variableSymbol, amount, iban, note, lang = 'cs' } = options;
  const title = lang === 'cs' ? 'Platební údaje:' : 'Payment Details:';

  const details = [
    { label: lang === 'cs' ? "Číslo účtu:" : "Account Number:", value: renderAccountNumber(accountNumber) },
  ];

  if (iban) {
    details.push({ label: "IBAN:", value: iban });
  }

  const isRf = variableSymbol.replace(/\s/g, '').toUpperCase().startsWith('RF');
  details.push({
    label: isRf ? (lang === 'cs' ? "Reference platby:" : "Payment Reference:")
                : (lang === 'cs' ? "Variabilní symbol:" : "Variable Symbol:"),
    value: variableSymbol,
  });

  if (note) {
    details.push({
        label: lang === 'cs' ? "Zpráva pro příjemce:" : "Message for recipient:",
        value: note
    });
  }

  details.push({ label: lang === 'cs' ? "Částka:" : "Amount:", value: amount });

  const rows = details
    .map(
      (d) =>
        `<tr>
          <td style="padding: 4px 8px; text-align: left; color: #555;">${d.label}</td>
          <td style="padding: 4px 8px; text-align: left;"><strong>${d.value}</strong></td>
         </tr>`
    )
    .join("");

  // margin-top is set to 0 as spacing is now handled by the verticalSpacer function.
  return `<div style="margin-top: 0; padding: 12px; border: 1px solid #e5e7eb; border-radius: 8px; background-color: #f9fafb;">
            <style>
              .festapp-payment-account a {
                color: inherit !important;
                text-decoration: none !important;
                pointer-events: none !important;
                cursor: text !important;
              }
            </style>
            <p style="margin-top:0; margin-bottom: 8px; font-weight: bold; color: #333;">${title}</p>
            <table style="width: 100%; border-collapse: collapse;">
              <tbody>${rows}</tbody>
            </table>
          </div>`;
};

// Constants to control spacing around the main text block.
export const spaceBeforeText = '25px';
export const spaceAfterText = '40px';

// Helper to create a paragraph with reset margins.
export const styledParagraph = (text: string) => `<p style="margin:0; padding:0; color: #333;">${text}</p>`;

// Helper to create a div-based spacer with a specific height.
export const verticalSpacer = (height: string) => `<div style="height:${height};"></div>`;
