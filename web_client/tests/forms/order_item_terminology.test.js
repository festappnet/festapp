import test from 'node:test';
import assert from 'node:assert/strict';
import cases from '../../../test/fixtures/order_item_terminology.json' with { type: 'json' };
import { JSDOM } from 'jsdom';
import { FeatureService } from '../../src/components/features/feature_service.js';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { PublicOrderStrings } from '../../src/components/forms/public_order_strings.js';
import { LocalizationService } from '../../src/services/localization_service.js';
import { generateFullOrder } from '../../../supabase/functions/_shared/orderOverview.ts';
import cs from '../../../assets/translations/cs.json' with { type: 'json' };
import en from '../../../assets/translations/en.json' with { type: 'json' };
import { readFileSync } from 'node:fs';
import { OrderItemStrings } from '../../src/components/eshop/order_item_strings.js';
import { TicketFieldBuilder } from '../../src/components/forms/fields/ticket_field_builder.js';
import { renderCardPaymentStatus } from '../../src/components/forms/card_payment_status.js';
import { scanResult } from '../../src/components/scan/scan_result.js';

for (const value of cases) {
  test(`occasion terminology: ${value.name}`, () => {
    assert.equal(FeatureService.usesTicketTerminology(value.features), value.tickets);
    for (const [language, catalog] of Object.entries({ cs, en })) {
      const dom = new JSDOM('<div id="result"></div>');
      const previousDocument = globalThis.document;
      const previousTranslations = LocalizationService.translations;
      globalThis.document = dom.window.document;
      LocalizationService.translations = catalog;
      try {
        const host = document.querySelector('#result');
        OrderResult.render(host, true, {}, {
          occasionFeatures: value.features,
          visibleFields: value.fields || [],
          communicationTone: 'formal',
        }, () => {});
        assert.equal(host.querySelector('.result-title').textContent,
          PublicOrderStrings.successTitle('formal', value.tickets));
        const html = generateFullOrder({}, [{ ticket_symbol: 'ABC', products: [] }], value.features, language);
        const label = language === 'cs'
          ? (value.tickets ? 'Vstupenka' : 'Přihláška')
          : (value.tickets ? 'Ticket' : 'Application');
        assert.ok(html.includes(`${label} ABC`));
      } finally {
        globalThis.document = previousDocument;
        LocalizationService.translations = previousTranslations;
        dom.window.close();
      }
    }
  });
}

test('all authored application variants are shared by app and web catalogs', () => {
  for (const locale of ['cs', 'en', 'de', 'pl', 'sk', 'uk']) {
    const catalog = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`, import.meta.url)));
    const web = JSON.parse(readFileSync(new URL(`../../public/assets/translations/${locale}.json`, import.meta.url)));
    assert.deepEqual(web.ApplicationTerminology, catalog.ApplicationTerminology);
    const strings = value => Object.values(value).flatMap(item =>
      typeof item === 'string' ? [item] : strings(item));
    for (const value of strings(catalog.ApplicationTerminology)) {
      assert.doesNotMatch(value, /vstupenk|vstupeniek|\btickets?\b|\bbilet\w*|квит/iu,
        `${locale}: application copy still mentions tickets`);
    }
    const previous = LocalizationService.translations;
    LocalizationService.translations = catalog;
    try {
      for (const key of ['ProductsDialog.changeTicketLabel', 'CardPayments.emailAccepted', 'Seating.ticket', 'Scanner.ticket_label']) {
        const application = LocalizationService.tr(`ApplicationTerminology.${key}`, { symbol: 'ABC' }, null);
        if (application == null) continue; // Sparse locales retain their existing catalog coverage.
        assert.equal(OrderItemStrings.text(key, { hasTickets: false, args: { symbol: 'ABC' } }), application);
        assert.equal(OrderItemStrings.text(key, { hasTickets: true, args: { symbol: 'ABC' } }), LocalizationService.tr(key, { symbol: 'ABC' }));
      }
    } finally { LocalizationService.translations = previous; }
  }
});

for (const hasTickets of [true, false]) {
  test(`form items, delivery and scanner use the owning occasion: ${hasTickets}`, () => {
    const dom = new JSDOM('<div id="host"></div>');
    const previous = globalThis.document;
    globalThis.document = dom.window.document;
    LocalizationService.translations = cs;
    try {
      const features = [{ code: 'ticket', is_enabled: hasTickets }];
      const callbacks = [];
      const session = Object.assign(new EventTarget(), {
        maxTickets: 3,
        state: { tickets: [{ fields: [] }, { fields: [] }] },
        subscribe: callback => { callbacks.push(callback); return () => {}; },
      });
      const field = TicketFieldBuilder.create({ id: 1, type: 'ticket', subFields: [] },
        { occasionFeatures: features }, session, () => {});
      assert.match(field.querySelector('.ticket-header span').textContent,
        hasTickets ? /^Vstupenka 1$/ : /^Přihláška 1$/);
      assert.match(field.querySelector('.btn-add-ticket').textContent,
        hasTickets ? /Přidat vstupenku/ : /Přidat přihlášku/);
      const host = document.querySelector('#host');
      renderCardPaymentStatus(host, { status: 'paid', deliveryState: 'accepted' }, { hasTickets });
      assert.doesNotMatch(host.textContent, hasTickets ? /přihlášk/ : /vstupenk/);
      const scanner = scanResult({ state: 'ready' }, true, hasTickets);
      assert.match(scanner, hasTickets ? /vstupenka/ : /přihláška/);
    } finally { globalThis.document = previous; dom.window.close(); }
  });
}
