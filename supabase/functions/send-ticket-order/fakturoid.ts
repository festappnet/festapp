import {
  assertFakturoidVariableSymbol,
  buildFakturoidInvoicePayload,
} from "./fakturoidPayload.ts";

export interface FakturoidConfig {
  client_id: string;
  client_secret: string;
  slug: string;
  subject_id: number;
  note?: string;
}

export async function useFakturoid(
  { client_id, client_secret, slug, subject_id, note }: FakturoidConfig,
  order: any,
  unitName: string,
  idempotencyKey: string,
  attachments: Array<{
    filename: string;
    content: Uint8Array;
    contentType: string;
    encoding: "binary";
  }>,
  mode: "prepare" | "attachment" = "attachment",
): Promise<string> {
  // 1) Get OAuth token
  const creds = btoa(`${client_id}:${client_secret}`);
  const tokenRes = await fetch(
    `https://app.fakturoid.cz/api/v3/oauth/token`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${creds}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        "User-Agent": "Festapp (no-reply@festapp.net)",
      },
      body: JSON.stringify({ grant_type: "client_credentials" }),
    },
  );
  if (!tokenRes.ok) throw new Error(`Token failed ${tokenRes.status}`);
  const { access_token } = await tokenRes.json();
  const apiHeaders = {
    Authorization: `Bearer ${access_token}`,
    "Content-Type": "application/json",
    "User-Agent": "Festapp (no-reply@festapp.net)",
  };

  // 2) Create Proforma with minimal payload
  const d = order.data;
  const originalVariableSymbol = String(order.payment_info.variable_symbol);
  const createBody = buildFakturoidInvoicePayload(
    order,
    unitName,
    idempotencyKey,
    subject_id,
    note,
  );

  const lookupUrl = new URL(
    `https://app.fakturoid.cz/api/v3/accounts/${slug}/invoices.json`,
  );
  lookupUrl.searchParams.set("custom_id", idempotencyKey);
  const lookupResponse = await fetch(lookupUrl, { headers: apiHeaders });
  if (!lookupResponse.ok) {
    throw new Error(`Fakturoid lookup failed ${lookupResponse.status}`);
  }
  const existing = await lookupResponse.json();
  let result = Array.isArray(existing) ? existing[0] : undefined;
  if (!result && mode === "prepare") {
    const invRes = await fetch(
      `https://app.fakturoid.cz/api/v3/accounts/${slug}/invoices.json`,
      {
        method: "POST",
        headers: apiHeaders,
        body: JSON.stringify(createBody),
      },
    );
    if (!invRes.ok) throw new Error(`Fakturoid create failed ${invRes.status}`);
    result = await invRes.json();
  }
  if (!result) throw new Error("FAKTUROID_INVOICE_NOT_READY");

  // The order response waits for Fakturoid's final CZK symbol.
  const patchBody: any = {
    client_name: `${d.name || ""} ${d.surname || ""}`.trim(),
    client_street: d.street,
    client_city: d.city,
    client_zip: d.zip,
    client_country: d.country,
    client_has_delivery_address: false,
    client_phone: d.phone,
  };
  if (String(order.payment_info.currency_code).toUpperCase() === "EUR") {
    patchBody.variable_symbol = originalVariableSymbol;
  }

  let patched = result;
  if (mode === "prepare") {
    const patchRes = await fetch(
    `https://app.fakturoid.cz/api/v3/accounts/${slug}/invoices/${result.id}.json`,
    {
      method: "PUT",
      headers: apiHeaders,
      body: JSON.stringify(patchBody),
    },
  );
    if (!patchRes.ok) {
      throw new Error(`Fakturoid patch failed ${patchRes.status}`);
    }
    patched = await patchRes.json();
  }
  const variableSymbol = String(patched.variable_symbol ?? "");
  if (!/^\d{1,10}$/.test(variableSymbol)) {
    throw new Error("FAKTUROID_VARIABLE_SYMBOL_INVALID");
  }
  if (String(order.payment_info.currency_code).toUpperCase() === "EUR") {
    assertFakturoidVariableSymbol(patched, originalVariableSymbol);
  } else {
    order.payment_info.variable_symbol = variableSymbol;
  }

  // PDF generation is kept in the email worker so the order waits only for VS.
  if (mode === "attachment" && patched.pdf_url) {
    await new Promise((r) => setTimeout(r, 1000));
    let pdfRes = await fetch(patched.pdf_url, {
      headers: { Authorization: `Bearer ${access_token}` },
    });

    if (pdfRes.status === 204) {
      console.info("Invoice PDF not ready; retrying once");
      await new Promise((r) => setTimeout(r, 1000));
      pdfRes = await fetch(patched.pdf_url, {
        headers: { Authorization: `Bearer ${access_token}` },
      });
    }

    if (pdfRes.ok) {
      const buf = new Uint8Array(await pdfRes.arrayBuffer());
      attachments.push({
        filename: `proforma-${patched.id}.pdf`,
        content: buf,
        contentType: "application/pdf",
        encoding: "binary",
      });
    } else {
      console.error("Could not fetch PDF, status:", pdfRes.status);
    }
  }
  return variableSymbol;
}
