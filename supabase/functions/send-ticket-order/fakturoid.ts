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

export interface FakturoidOrder {
  data?: {
    name?: string;
    surname?: string;
    street?: string;
    city?: string;
    zip?: string;
    country?: string;
    phone?: string;
  };
  payment_info: {
    amount: number;
    currency_code: string;
    variable_symbol: string | number;
    account_number: string;
    account_number_human_readable: string;
  };
}

export type FakturoidAttachment = {
  filename: string;
  content: Uint8Array;
  contentType: "application/pdf";
  encoding: "binary";
};

type Invoice = { id: number; variable_symbol?: unknown; pdf_url?: string };
type InvoiceRequest = {
  config: FakturoidConfig;
  order: FakturoidOrder;
  commandId: string;
};

/** The checkout phase alone may create an invoice; the email phase only reads it. */
export function createFakturoidGateway(fetcher: typeof fetch = fetch) {
  // Finish API failures inside the checkout worker so it can cancel the order.
  const request: typeof fetch = (input, init) =>
    fetcher(input, { ...init, signal: AbortSignal.timeout(30_000) });

  async function access(config: FakturoidConfig) {
    const response = await request("https://app.fakturoid.cz/api/v3/oauth/token", {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${config.client_id}:${config.client_secret}`)}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        "User-Agent": "Festapp (no-reply@festapp.net)",
      },
      body: JSON.stringify({ grant_type: "client_credentials" }),
    });
    if (!response.ok) throw new Error(`Token failed ${response.status}`);
    const { access_token } = await response.json();
    if (!access_token) throw new Error("FAKTUROID_TOKEN_MISSING");
    return {
      token: String(access_token),
      headers: {
        Authorization: `Bearer ${access_token}`,
        "Content-Type": "application/json",
        "User-Agent": "Festapp (no-reply@festapp.net)",
      },
    };
  }

  async function findInvoice(
    config: FakturoidConfig,
    commandId: string,
    headers: Record<string, string>,
  ): Promise<Invoice | undefined> {
    const url = new URL(
      `https://app.fakturoid.cz/api/v3/accounts/${config.slug}/invoices.json`,
    );
    url.searchParams.set("custom_id", commandId);
    const response = await request(url, { headers });
    if (!response.ok) {
      throw new Error(`Fakturoid lookup failed ${response.status}`);
    }
    const invoices = await response.json();
    if (!Array.isArray(invoices) || invoices.length > 1 || response.headers.get("Link")?.includes('rel="next"')) {
      throw new Error("FAKTUROID_INVOICE_LOOKUP_AMBIGUOUS");
    }
    return invoices[0];
  }

  function variableSymbol(invoice: Invoice, order: FakturoidOrder): string {
    const value = String(invoice.variable_symbol ?? "");
    if (!/^\d{1,10}$/.test(value)) {
      throw new Error("FAKTUROID_VARIABLE_SYMBOL_INVALID");
    }
    assertFakturoidVariableSymbol(invoice, order.payment_info.variable_symbol);
    return value;
  }

  async function preparePayment(
    { config, order, commandId, unitName }: InvoiceRequest & {
      unitName: string;
    },
  ): Promise<string> {
    const { headers } = await access(config);
    let invoice = await findInvoice(config, commandId, headers);
    if (!invoice) {
      const response = await request(
        `https://app.fakturoid.cz/api/v3/accounts/${config.slug}/invoices.json`,
        {
          method: "POST",
          headers,
          body: JSON.stringify(buildFakturoidInvoicePayload(
            order,
            unitName,
            commandId,
            config.subject_id,
            config.note,
          )),
        },
      );
      if (!response.ok) {
        throw new Error(`Fakturoid create failed ${response.status}`);
      }
      invoice = await response.json();
    }
    if (!invoice) throw new Error("FAKTUROID_INVOICE_NOT_READY");
    variableSymbol(invoice, order);
    const data = order.data ?? {};
    const clientName = `${data.name || ""} ${data.surname || ""}`.trim();
    if (clientName) {
      const patchBody: Record<string, unknown> = {
        client_name: clientName,
        client_street: data.street,
        client_city: data.city,
        client_zip: data.zip,
        client_country: data.country,
        client_has_delivery_address: false,
        client_phone: data.phone,
      };
      patchBody.variable_symbol = String(order.payment_info.variable_symbol);
      const response = await request(
        `https://app.fakturoid.cz/api/v3/accounts/${config.slug}/invoices/${invoice.id}.json`,
        { method: "PUT", headers, body: JSON.stringify(patchBody) },
      );
      if (!response.ok) throw new Error(`Fakturoid patch failed ${response.status}`);
      invoice = await response.json();
    }
    if (!invoice) throw new Error("FAKTUROID_INVOICE_NOT_READY");
    return variableSymbol(invoice, order);
  }

  async function getEmailAttachment(
    { config, order, commandId }: InvoiceRequest,
  ): Promise<{ variableSymbol: string; attachment?: FakturoidAttachment }> {
    const { headers, token } = await access(config);
    const invoice = await findInvoice(config, commandId, headers);
    if (!invoice) throw new Error("FAKTUROID_INVOICE_NOT_READY");

    const result: { variableSymbol: string; attachment?: FakturoidAttachment } = {
      variableSymbol: variableSymbol(invoice, order),
    };
    if (invoice.pdf_url) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      let response = await request(invoice.pdf_url, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (response.status === 204) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        response = await request(invoice.pdf_url, {
          headers: { Authorization: `Bearer ${token}` },
        });
      }
      if (response.ok) {
        result.attachment = {
          filename: `proforma-${invoice.id}.pdf`,
          content: new Uint8Array(await response.arrayBuffer()),
          contentType: "application/pdf",
          encoding: "binary",
        };
      } else {
        console.error("Could not fetch PDF, status:", response.status);
      }
    }
    return result;
  }

  async function deleteInvoice({ config, commandId, variableSymbol: expected }: {
    config: FakturoidConfig;
    commandId?: string | null;
    variableSymbol: string | number;
  }): Promise<void> {
    const { headers } = await access(config);
    let invoice: Invoice | undefined;
    if (commandId) {
      invoice = await findInvoice(config, commandId, headers);
    } else {
      // Historical invoices predate checkout UUIDs. Never guess among matches.
      if (!/^\d{1,10}$/.test(String(expected))) {
        throw new Error("FAKTUROID_VARIABLE_SYMBOL_INVALID");
      }
      const url = new URL(
        `https://app.fakturoid.cz/api/v3/accounts/${config.slug}/invoices/search.json`,
      );
      url.searchParams.set("query", String(expected));
      const response = await request(url, { headers });
      if (!response.ok) throw new Error(`Fakturoid lookup failed ${response.status}`);
      const invoices = await response.json();
      if (!Array.isArray(invoices) || invoices.length > 1 ||
        response.headers.get("Link")?.includes('rel="next"')) {
        throw new Error("FAKTUROID_INVOICE_LOOKUP_AMBIGUOUS");
      }
      if (invoices[0]) {
        const id = invoices[0].id;
        if (!Number.isSafeInteger(id) || id <= 0) throw new Error("FAKTUROID_INVOICE_ID_INVALID");
        const detail = await request(
          `https://app.fakturoid.cz/api/v3/accounts/${config.slug}/invoices/${id}.json`,
          { headers },
        );
        // It may have been removed independently after the search returned it.
        if (detail.status === 404) return;
        if (!detail.ok) throw new Error(`Fakturoid lookup failed ${detail.status}`);
        invoice = await detail.json();
      }
    }
    // Also completes retries after the invoice was removed but SQL failed.
    if (!invoice) return;
    assertFakturoidVariableSymbol(invoice, expected);
    if (!Number.isSafeInteger(invoice.id) || invoice.id <= 0) {
      throw new Error("FAKTUROID_INVOICE_ID_INVALID");
    }
    const response = await request(
      `https://app.fakturoid.cz/api/v3/accounts/${config.slug}/invoices/${invoice.id}.json`,
      { method: "DELETE", headers },
    );
    if (response.status !== 204 && response.status !== 404) {
      throw new Error(`Fakturoid delete failed ${response.status}`);
    }
  }

  return { preparePayment, getEmailAttachment, deleteInvoice };
}

export const fakturoidGateway = createFakturoidGateway();
