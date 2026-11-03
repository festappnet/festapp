import { DEFAULT_META_SURCHARGE_CURRENCY } from "./constants.ts";

/**
 * Single product's resolved meta-surcharge amount (after virtual-mode + validity check).
 * Negative amounts represent slevy/discounts.
 */
export interface MetaSurchargeAmount {
  amount: number;
  currency: string;
}

/**
 * Extract a virtual-mode meta surcharge from a product. Returns null when:
 *   - DepositFeature is not in virtual mode (real mode uses payment-linked deposit
 *     so showing meta_surcharge would be misleading)
 *   - Product has no meta_surcharge data
 *   - Amount is 0, missing, or non-finite
 *
 * Currency falls back to DEFAULT_META_SURCHARGE_CURRENCY when admin left the
 * per-product field empty — matches the admin input placeholder.
 */
export function extractMetaSurcharge(
  product: any,
  depositMode: string | undefined,
): MetaSurchargeAmount | null {
  if (depositMode !== 'virtual') return null;
  const ms = product?.data?.meta_surcharge;
  if (!ms) return null;
  const raw = ms.amount;
  const num = typeof raw === 'number' ? raw : (raw != null ? Number(raw) : null);
  if (num === null || !Number.isFinite(num) || num === 0) return null;
  return {
    amount: num,
    currency: ms.currency || DEFAULT_META_SURCHARGE_CURRENCY,
  };
}

/**
 * Group amounts by currency and sum them. Currencies whose net sum is 0
 * (e.g. equal positive and negative cancelling out) are dropped so callers
 * can render the result directly without a zero check.
 */
export function aggregateMetaSurchargeSums(
  amounts: Iterable<MetaSurchargeAmount>,
): Array<{ currency: string; sum: number }> {
  const byCurrency = new Map<string, number>();
  for (const { amount, currency } of amounts) {
    byCurrency.set(currency, (byCurrency.get(currency) || 0) + amount);
  }
  return Array.from(byCurrency.entries())
    .filter(([, sum]) => sum !== 0)
    .map(([currency, sum]) => ({ currency, sum }));
}

/**
 * Format a signed amount as "+ X" / "− X" using a caller-supplied formatter for
 * the absolute part. The PDF prefers raw "150 EUR" (3-letter code, matches the
 * organizer info), the email prefers Intl currency style (e.g. "150 €"); both
 * share the sign + abs convention.
 */
export function formatSignedMetaSurcharge(
  amount: number,
  currency: string,
  formatAmount: (absAmount: number, currency: string) => string,
): string {
  const sign = amount < 0 ? '− ' : '+ ';
  return `${sign}${formatAmount(Math.abs(amount), currency)}`;
}
