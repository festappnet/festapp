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
    return Array.isArray(invoices) ? invoices[0] : undefined;
  }

  function variableSymbol(invoice: Invoice, order: FakturoidOrder): string {
    const value = String(invoice.variable_symbol ?? "");
    if (!/^\d{1,10}$/.test(value)) {
      throw new Error("FAKTUROID_VARIABLE_SYMBOL_INVALID");
    }
    // EUR's RF reference is generated from the order VS by PostgreSQL. Until
    // that payment-pairing contract changes, Fakturoid must echo the same VS.
    if (order.payment_info.currency_code.trim().toUpperCase() === "EUR") {
      assertFakturoidVariableSymbol(invoice, order.payment_info.variable_symbol);
    }
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
      if (order.payment_info.currency_code.trim().toUpperCase() === "EUR") {
        patchBody.variable_symbol = String(order.payment_info.variable_symbol);
      }
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

  return { preparePayment, getEmailAttachment };
}

export const fakturoidGateway = createFakturoidGateway();
