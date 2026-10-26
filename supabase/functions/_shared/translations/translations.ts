// File: ../_shared/translations.ts
// PURPOSE: This file aggregates language-specific translations into the
// single 'translations' object expected by the rest of the application.

import { csTranslations } from './translations.cs.ts';
import { enTranslations } from './translations.en.ts';

export const translations = {
  cs: csTranslations,
  en: enTranslations,
};

// You can also re-export any shared types or helpers if other parts
// of your app need them directly, for example:
export * from './payment-details.helpers.ts';