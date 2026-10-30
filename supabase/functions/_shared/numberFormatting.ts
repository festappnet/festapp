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
