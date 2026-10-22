export function formatCurrency(amount: number, currencyCode = "CZK") {
  return new Intl.NumberFormat("cs-CZ", {
    style: "currency",
    currency: currencyCode,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount);
}

export function formatDatetime(
  datetime: string | null,
  language = "cs",
): string | null {
  // Check if the datetime is null, undefined, or an empty string.
  // If it is, return null immediately.
  if (!datetime) {
    return null;
  }

  // If datetime is a valid string, proceed with the original formatting.
  return new Intl.DateTimeFormat(language === "cs" ? "cs-CZ" : language, {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(datetime));
}

// Formats an IBAN string by inserting spaces for readability, e.g., "CZ59 2010 0000 0020 0280 8176"
export function formatIBAN(iban: string | undefined | null): string {
  if (!iban || typeof iban !== "string" || iban.length < 4) {
    // Return original value or empty string if it's not a valid string or too short
    return iban || "";
  }
  // Takes the first 4 characters (e.g., "CZ59")
  const firstPart = iban.substring(0, 4);
  // Takes the rest of the IBAN string
  const rest = iban.substring(4);

  const chunks = [firstPart]; // Start with the first part
  // Loop through the rest of the IBAN string and split it into 4-character chunks
  for (let i = 0; i < rest.length; i += 4) {
    chunks.push(rest.substring(i, i + 4));
  }
  // Join all chunks with a space
  return chunks.join(" ");
}
