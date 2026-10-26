export type AgreementOrganizer = {
  name: string;
  ico: string;
  dic: string;
  address: string;
  email: string;
  phone: string;
  account: string;
};

export type AgreementConfig = {
  organizer: AgreementOrganizer;
  paymentClause: string;
  termsClause: string;
  logoUrl: string;
  fontUrl: string;
};

const requiredOrganizerKeys: Array<keyof AgreementOrganizer> = [
  "name", "ico", "dic", "address", "email", "phone", "account",
];

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`agreement_config_missing_${field}`);
  }
  return value.trim();
}

function requiredHttpUrl(value: unknown, field: string): string {
  const result = requiredString(value, field);
  const url = new URL(result);
  if (!/^https?:$/.test(url.protocol)) throw new Error(`agreement_config_invalid_${field}`);
  return result;
}

export function parseAgreementConfig(services: unknown): AgreementConfig {
  if (!Array.isArray(services)) throw new Error("agreement_config_missing_service");
  const service = services.find((candidate) =>
    candidate && typeof candidate === "object" &&
    (candidate as Record<string, unknown>).type === "AGREEMENT_PDF"
  ) as Record<string, unknown> | undefined;
  const data = service?.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("agreement_config_missing_service");
  }
  const value = data as Record<string, unknown>;
  const rawOrganizer = value.organizer;
  if (!rawOrganizer || typeof rawOrganizer !== "object" || Array.isArray(rawOrganizer)) {
    throw new Error("agreement_config_missing_organizer");
  }
  const organizerValue = rawOrganizer as Record<string, unknown>;
  const organizer = Object.fromEntries(requiredOrganizerKeys.map((key) => [
    key,
    requiredString(organizerValue[key], `organizer_${key}`),
  ])) as AgreementOrganizer;
  return {
    organizer,
    paymentClause: requiredString(value.paymentClause, "payment_clause"),
    termsClause: requiredString(value.termsClause, "terms_clause"),
    logoUrl: requiredHttpUrl(value.logoUrl, "logo_url"),
    fontUrl: requiredHttpUrl(value.fontUrl, "font_url"),
  };
}
