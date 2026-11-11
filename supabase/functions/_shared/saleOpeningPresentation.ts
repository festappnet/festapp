import { escapeEmailHtml, waitlistActionLink } from './emailActionLink.ts';
export const saleOpeningCopy = {
  "cs": {
    "subject": "Prodej byl spuštěn",
    "action": "Přejít na prodej",
    "disclaimer": "Přihlášení nezajišťuje rezervaci ani přednostní nákup.",
    "unsubscribe": "Odhlásit upozornění"
  },
  "en": {
    "subject": "Sales are open",
    "action": "Go to sales",
    "disclaimer": "Signing up does not reserve tickets or provide priority access.",
    "unsubscribe": "Unsubscribe"
  },
  "sk": {
    "subject": "Predaj bol spustený",
    "action": "Prejsť na predaj",
    "disclaimer": "Prihlásenie nezaisťuje rezerváciu ani prednostný nákup.",
    "unsubscribe": "Odhlásiť upozornenie"
  },
  "de": {
    "subject": "Der Verkauf hat begonnen",
    "action": "Zum Verkauf",
    "disclaimer": "Die Anmeldung reserviert keine Tickets und gewährt keinen bevorzugten Zugang.",
    "unsubscribe": "Benachrichtigung abbestellen"
  },
  "pl": {
    "subject": "Sprzedaż została otwarta",
    "action": "Przejdź do sprzedaży",
    "disclaimer": "Zapis nie zapewnia rezerwacji ani pierwszeństwa zakupu.",
    "unsubscribe": "Zrezygnuj z powiadomienia"
  },
  "uk": {
    "subject": "Продаж розпочато",
    "action": "Перейти до продажу",
    "disclaimer": "Підписка не гарантує бронювання чи пріоритетної покупки.",
    "unsubscribe": "Відписатися"
  }
} as const;
export const saleOpeningRegistrationCopy = {
  "cs": [
    "Registrace byla otevřena",
    "Přejít na registraci"
  ],
  "en": [
    "Registration is open",
    "Go to registration"
  ],
  "sk": [
    "Registrácia bola otvorená",
    "Prejsť na registráciu"
  ],
  "de": [
    "Die Anmeldung ist geöffnet",
    "Zur Anmeldung"
  ],
  "pl": [
    "Rejestracja została otwarta",
    "Przejdź do rejestracji"
  ],
  "uk": [
    "Реєстрацію відкрито",
    "Перейти до реєстрації"
  ]
} as const;
export function saleOpeningUrl(webLink: string, formLink: string, purpose?: string, token?: string): string {
 const base = new URL(webLink);
 if ((base.protocol !== 'https:' && !(base.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(base.hostname))) || base.username || base.password || base.search || base.hash) throw new Error('sale_opening_origin_invalid');
 const url = new URL(`/form/${encodeURIComponent(formLink)}`, base);
 if (purpose && token) url.hash = new URLSearchParams({ sale_opening: purpose, token }).toString();
 return url.href;
}
export function saleOpeningSubstitutions(lang: string, title: string, action: string, unsubscribe: string, options: {hasTickets?: boolean} = {}) {
 const copy = saleOpeningCopy[lang as keyof typeof saleOpeningCopy];
 if (!copy) throw new Error('sale_opening_locale_invalid');
 const registration = saleOpeningRegistrationCopy[lang as keyof typeof saleOpeningRegistrationCopy];
 const subject = options.hasTickets === false ? registration[0] : copy.subject;
 return {occasionTitle: title,sale_opening_subject:subject,sale_opening_heading:subject,
  sale_opening_disclaimer:copy.disclaimer,
  sale_opening_action:waitlistActionLink(escapeEmailHtml(action),options.hasTickets === false ? registration[1] : copy.action),
  sale_opening_unsubscribe:`<a href="${escapeEmailHtml(unsubscribe)}" rel="noreferrer noopener" referrerpolicy="no-referrer">${copy.unsubscribe}</a>`};
}
