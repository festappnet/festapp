export function buildFakturoidInvoicePayload(
  order: any,
  unitName: string,
  idempotencyKey: string,
  subjectId: number,
  note?: string,
  issuedOn = new Date().toISOString().slice(0, 10),
): Record<string, unknown> {
  const total = Number(order.payment_info.amount).toFixed(2);
  const body: Record<string, unknown> = {
    custom_id: idempotencyKey,
    document_type: "proforma",
    subject_id: subjectId,
    issued_on: issuedOn,
    taxable_fulfillment_due: issuedOn,
    currency: order.payment_info.currency_code,
    iban: order.payment_info.account_number,
    bank_account: order.payment_info.account_number_human_readable,
    lines: [{
      name: unitName,
      quantity: 1,
      unit_name: unitName.slice(0, 10),
      unit_price: total,
      vat_rate: 0,
    }],
  };
  if (order.data?.discount) {
    // Existing adapter uses zero VAT. Preserve each already charged SQL line.
    // This check is integrity verification, never a second price calculation.
    const minor = (value: unknown): bigint => {
      const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
      if (!match) throw new Error("FAKTUROID_ORDER_SNAPSHOT_INVALID");
      return BigInt(match[1]) * 100n + BigInt((match[2] ?? "").padEnd(2, "0"));
    };
    const products = order.data.tickets.flatMap((ticket: any) => ticket.products);
    if (!products.length || products.reduce((sum: bigint, p: any) => sum + minor(p.price), 0n) !== minor(order.payment_info.amount)) {
      throw new Error("FAKTUROID_ORDER_SNAPSHOT_INVALID");
    }
    body.lines = products.map((p: any) => ({
      name: p.title, quantity: 1, unit_price: (minor(p.price) / 100n).toString() + "." + (minor(p.price) % 100n).toString().padStart(2, "0"), vat_rate: 0,
    }));
  }
  body.variable_symbol = String(order.payment_info.variable_symbol);
  if (note) body.note = note;
  return body;
}

export function assertFakturoidVariableSymbol(
  invoice: { variable_symbol?: unknown },
  expected: unknown,
): void {
  if (String(invoice.variable_symbol ?? "") !== String(expected)) {
    throw new Error("FAKTUROID_VARIABLE_SYMBOL_MISMATCH");
  }
}
