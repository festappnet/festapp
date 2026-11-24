import 'dart:convert';
import 'dart:io';

import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:festapp_core/email_templates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/email_preview_context_loader.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/ticket_feature.dart';

ProductsEditBundle bundle(List<ProductModel> products) => ProductsEditBundle(
  products: products,
  productTypes: [ProductTypeModel(id: 1, title: 'Vstupné')],
  inventoryPools: [],
  inventoryContexts: [],
  forms: [],
);
void main() {
  test(
    'preview resolves form override and organizer inheritance canonically',
    () async {
      for (final formTone in [null, 'inherit', 'formal', 'informal']) {
        final result = await loadEmailPreviewContext(
          OccasionModel(
            id: 3,
            title: 'Duchovní obnova',
            link: 'obnova',
            isOpen: true,
            isHidden: false,
            isPromoted: false,
          ),
          inheritedTone: 'informal',
          loadForms: (_) async => [
            FormBundle.fromJson({
              'id': 1,
              'customer_cancellation_available': formTone == 'formal',
              'data': {
                'communication_tone': formTone,
                if (formTone == 'formal') 'show_payment_qr_in_email': false,
              },
            }),
          ],
          loadProducts: (_) async => bundle([]),
        );
        expect(
          result.context.communicationTone,
          formTone == 'formal' ? 'formal' : 'informal',
        );
        expect(result.context.cancellationAvailable, formTone == 'formal');
        expect(result.context.inlinePaymentQr, formTone != 'formal');
        expect(result.context.singleApplication, true);
        expect(result.unavailable, false);
      }
    },
  );
  test('cash-only previews use the open form and omit bank collection', () async {
    final result = await loadEmailPreviewContext(
      OccasionModel(
        id: 3, title: 'Hasičský ples', link: 'ples', isOpen: true,
        isHidden: false, isPromoted: false,
      ),
      loadForms: (_) async => [
        FormBundle.fromJson({
          'id': 1, 'is_open': false,
          'data': {'payments': {'bankEnabled': true}},
        }),
        FormBundle.fromJson({
          'id': 2, 'is_open': true,
          'data': {
            'payments': {
              'cashEnabled': true,
              'bankEnabled': false,
              'providerConnections': {'stripe': 'previous-recipient'},
            },
            'show_payment_qr_in_email': true,
          },
        }),
      ],
      loadProducts: (_) async => bundle([]),
    );
    expect(result.context.paymentMethod, 'cash');
    final examples = EmailPreviewExamples.fromJson(
      jsonDecode(File('assets/email_templates/preview_examples.json').readAsStringSync()),
      context: result.context,
    );
    final confirmation = examples.scenariosFor('TICKET_ORDER_CONFIRMATION')
        .firstWhere((sample) => sample.locale == 'cs');
    expect(confirmation.scenario, 'cash-unpaid');
    expect(confirmation.values['accountNumber'], isEmpty);
    expect(confirmation.paymentQrSample, isNull);
    expect(confirmation.composeHtml('{{balanceReasoning}}'), contains('K úhradě na místě'));
    final paid = examples.scenariosFor('TICKET_ORDER_PAYMENT_DONE')
        .firstWhere((sample) => sample.locale == 'cs');
    final paidHtml = paid.composeHtml('{{balanceReasoning}}');
    expect(paid.scenario, 'cash-paid');
    expect(paidHtml, contains('Objednávka je plně uhrazena.'));
    expect(paidHtml, isNot(contains('K úhradě na místě')));
    expect(paidHtml, isNot(contains('U vstupu.')));
    for (final code in [
      'TICKET_ORDER_CONFIRMATION', 'TICKET_ORDER_UPDATE', 'TICKET_ORDER_PAYMENT_DONE',
      'TICKET_ORDER_REMINDER', 'TICKET_ORDER_STORNO',
    ]) {
      for (final sample in examples.scenariosFor(code)) {
        expect(sample.paymentQrSample, isNull);
        expect(
          sample.composeHtml('{{balanceReasoning}}'),
          isNot(contains(emailPreviewPaymentQrSource)),
        );
      }
    }
  });
  test('each order preview matches collection eligibility and payment state', () {
    final fixture = jsonDecode(
      File('assets/email_templates/preview_examples.json').readAsStringSync(),
    );
    EmailPreviewExamples examples(String method) => EmailPreviewExamples.fromJson(
      fixture,
      context: EmailPreviewContext(paymentMethod: method, cancellationAvailable: true),
    );
    const collectable = [
      'TICKET_ORDER_CONFIRMATION', 'TICKET_ORDER_UPDATE', 'TICKET_ORDER_REMINDER',
    ];
    for (final method in ['bank', 'cash', 'stripe']) {
      final samples = examples(method);
      for (final code in collectable) {
        final example = samples.scenariosFor(code)
            .firstWhere((sample) => sample.locale == 'cs');
        expect(example.paymentQrSample != null, method == 'bank');
      }
      final paid = samples.scenariosFor('TICKET_ORDER_PAYMENT_DONE')
          .firstWhere((sample) => sample.locale == 'cs');
      expect(paid.scenario, endsWith('paid'));
      expect(paid.values['paymentAction'], isEmpty);
      expect(paid.paymentQrSample, isNull);
      expect(paid.values['balanceReasoning'], isNot(contains('K úhradě na místě')));
      final cancelled = samples.scenariosFor('TICKET_ORDER_STORNO');
      for (final sample in cancelled) {
        expect(sample.contextDefaults['preview_payment_method'], method);
        expect(sample.contextDefaults['preview_collection_allowed'], 'false');
        expect(sample.values['paymentAction'], isEmpty);
        expect(sample.paymentQrSample, isNull);
        expect(sample.requiredLinks.every((link) => link.companionHtml.isEmpty), isTrue);
      }
    }
    final deposit = examples('bank').scenariosFor('TICKET_ORDER_PAYMENT_DONE')
        .firstWhere((sample) => sample.scenario == 'deposit' && sample.locale == 'cs');
    expect(deposit.values['amount'], contains('300'));
    expect(deposit.values['paymentAction'], contains('500'));
    expect(deposit.values['paymentAction'], isNot(contains('300')));
    expect(deposit.paymentQrSample?['amount'], 500);
  });
  for (final blueprintEnabled in [false, true]) {
    test(
      'application examples respect blueprint multiplicity $blueprintEnabled with and without a catalog',
      () {
        final data = jsonDecode(
          File('assets/email_templates/preview_examples.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        for (final products in [
          <EmailPreviewProduct>[],
          const [
            EmailPreviewProduct(title: 'Účast', typeTitle: 'Kurz', price: 1000),
          ],
        ]) {
          final examples = EmailPreviewExamples.fromJson(
            data,
            context: EmailPreviewContext(
              ticketsEnabled: false,
              blueprintEnabled: blueprintEnabled,
              products: products,
            ),
          );
          for (final code in [
            'TICKET_ORDER_CONFIRMATION',
            'TICKET_ORDER_UPDATE',
            'TICKET_ORDER_PAYMENT_DONE',
            'TICKET_ORDER_REMINDER',
            'TICKET_ORDER_STORNO',
          ]) {
            for (final scenario in examples.scenariosFor(code)) {
              if (scenario.values.containsKey('fullOrder')) {
                expect(scenario.values['fullOrder'], contains('X3425W8H2U'));
                expect(
                  scenario.values['fullOrder']!.contains('X3427M4R9K'),
                  blueprintEnabled,
                );
              }
              if (!blueprintEnabled) {
                expect(
                  scenario.values['changeOverview'] ?? '',
                  isNot(contains('X3427M4R9K')),
                );
              }
              if (!blueprintEnabled &&
                  products.isNotEmpty &&
                  code == 'TICKET_ORDER_CONFIRMATION' &&
                  scenario.scenario == 'unpaid') {
                expect(scenario.values['amount'], contains('1000'));
                expect(scenario.values['fullOrder'], isNot(contains('2000')));
              }
            }
          }
        }
      },
    );
  }
  test('configured bank example follows sample currency in scalar and canonical rich values', () {
    final examples = EmailPreviewExamples.fromJson(
      jsonDecode(
        File('assets/email_templates/preview_examples.json').readAsStringSync(),
      ),
      context: const EmailPreviewContext(
        products: [
          EmailPreviewProduct(
            title: 'Kurz',
            typeTitle: 'Účast',
            price: 200,
            currency: 'EUR',
          ),
        ],
      ),
    );
    const accounts = [
      EmailPreviewPaymentAccount(
        accountNumber: '123456789/2010',
        iban: 'CZ65 2010 0000 0012 3456 7890',
        currencies: ['CZK'],
      ),
      EmailPreviewPaymentAccount(
        accountNumber: 'EUR account',
        iban: 'SK12 3456 0000 0012 3456 7890',
        currencies: ['EUR'],
      ),
    ];
    for (final scenario in examples.scenariosFor(
      'TICKET_ORDER_CONFIRMATION',
      paymentAccounts: accounts,
    )) {
      if (scenario.contextDefaults['preview_payment_method'] != 'bank' ||
          scenario.contextDefaults['preview_collection_allowed'] != 'true') {
        expect(scenario.values['accountNumber'], isEmpty);
        expect(scenario.values['iban'], isEmpty);
        continue;
      }
      expect(scenario.values['accountNumber'], 'EUR account');
      expect(scenario.values['iban'], accounts[1].iban);
      if (scenario.scenario == 'unpaid')
        expect(scenario.values['balanceReasoning'], contains(accounts[1].iban));
    }
    for (final scenario in examples.scenariosFor(
      'TICKET_ORDER_REMINDER',
      paymentAccounts: accounts,
    )) {
      if (scenario.contextDefaults['preview_payment_method'] != 'bank' ||
          scenario.contextDefaults['preview_collection_allowed'] != 'true') {
        expect(
          scenario.values['paymentDetails'] ?? '',
          isNot(contains(accounts[1].iban)),
        );
        continue;
      }
      expect(scenario.values['paymentDetails'], contains(accounts[1].iban));
      expect(
        scenario.values['paymentDetails'],
        isNot(contains('0000000000/0000')),
      );
    }
    final noMatch = examples
        .scenariosFor(
          'TICKET_ORDER_CONFIRMATION',
          paymentAccounts: [accounts.first],
        )
        .first;
    expect(
      noMatch.values['accountNumber'],
      isNot(accounts.first.accountNumber),
    );
    expect(noMatch.values['fullOrder'], contains('Kurz'));
  });
  test(
    'remote banner preview uses only canonical images from resolved wrapper',
    () {
      const context = EmailAuthoringContext(
        senderAddress: 'info@festapp.net',
        wrapperHtml:
            '<div><img src="https://img.festapp.net/images/banner.png">'
            '<img src="https://a.img.festapp.net/assets/banner.svg">'
            '<img src="https://tracker.invalid/pixel.png">'
            '<img src="https://img.festapp.net:8443/images/banner.png">'
            '<img src="https://user@img.festapp.net/images/banner.png">'
            '<img src="https://img.festapp.net/images/%2e%2e/pixel.png">'
            '<img src="cid:payment-qr">{{content}}</div>',
      );
      expect(context.bannerImageSources, {
        'https://img.festapp.net/images/banner.png',
        'https://a.img.festapp.net/assets/banner.svg',
      });
      expect(
        const EmailAuthoringContext(senderAddress: 'info@festapp.net')
            .bannerImageSources,
        isEmpty,
      );
    },
  );
  test(
    'occasion sampler uses scoped catalog with actual prices in one currency',
    () async {
      final occasion = OccasionModel(
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        id: 42,
        title: 'Podzimní koncert',
        features: [TicketFeature(code: 'ticket', isEnabled: true)],
        link: 'concert',
      );
      var requests = 0;
      final result = await loadEmailPreviewContext(
        occasion,
        loadForms: (_) async => [],
        loadProducts: (link) async {
          expect(link, 'concert');
          requests++;
          return bundle([
            ProductModel(
              id: 1,
              title: 'Skryté',
              price: 999,
              isHidden: true,
              currencyCode: 'CZK',
            ),
            ProductModel(
              id: 2,
              title: 'Přízemí',
              price: 750,
              productTypeId: 1,
              currencyCode: 'CZK',
            ),
            ProductModel(
              id: 3,
              title: 'Jiná měna',
              price: 30,
              currencyCode: 'EUR',
            ),
            ProductModel(
              id: 4,
              title: 'Balkon',
              price: 450,
              productTypeId: 1,
              currencyCode: 'CZK',
            ),
          ]);
        },
      );
      expect(requests, 1);
      expect(result.unavailable, isFalse);
      expect(result.context.products.map((p) => p.title), [
        'Přízemí',
        'Balkon',
      ]);
      final examples = EmailPreviewExamples.fromJson(
        jsonDecode(
          File('assets/email_templates/preview_examples.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>,
        context: result.context,
      );
      expect(examples.usesOccasionProducts, isTrue);
      final scenario = examples.scenariosFor('TICKET_ORDER_CONFIRMATION').first;
      expect(scenario.values['occasionTitle'], 'Podzimní koncert');
      expect(scenario.values['fullOrder'], contains('Vstupné: Přízemí'));
      expect(scenario.values['fullOrder'], contains('Balkon'));
      expect(scenario.values['amount'], contains('1200'));
      expect(scenario.values['fullOrder'], isNot(contains('Jiná měna')));
    },
  );
  for (final enabled in [true, false]) {
    test(
      'occasion sampler preserves ticket feature $enabled even without catalog access',
      () async {
        final occasion = OccasionModel(
          isOpen: true,
          isHidden: false,
          isPromoted: false,
          id: 42,
          title: 'Kurz',
          link: 'course',
          features: [TicketFeature(code: 'ticket', isEnabled: enabled)],
        );
        for (final denied in [false, true]) {
          final result = await loadEmailPreviewContext(
            occasion,
            loadForms: (_) async => [],
            loadProducts: (_) async {
              if (denied) throw StateError('denied');
              return bundle([
                ProductModel(
                  id: 1,
                  title: 'Účastnický poplatek',
                  price: 1000,
                  currencyCode: 'CZK',
                ),
              ]);
            },
          );
          expect(result.context.ticketsEnabled, enabled);
          final examples = EmailPreviewExamples.fromJson(
            jsonDecode(
              File('assets/email_templates/preview_examples.json')
                  .readAsStringSync(),
            ) as Map<String, dynamic>,
            context: result.context,
          );
          final scenario = examples
              .scenariosFor('TICKET_ORDER_CONFIRMATION')
              .first;
          expect(
            scenario.values['fullOrder'],
            contains(enabled ? 'Vstupenka X3425W8H2U' : 'Přihláška X3425W8H2U'),
          );
        }
      },
    );
  }
  test(
    'denied catalog yields a labelled model fallback retaining occasion title',
    () async {
      final result = await loadEmailPreviewContext(
        OccasionModel(
          isOpen: true,
          isHidden: false,
          isPromoted: false,
          id: 42,
          title: 'Ples',
          link: 'ball',
        ),
        loadForms: (_) async => [],
        loadProducts: (_) async => throw StateError('not permitted'),
      );
      expect(result.unavailable, isTrue);
      expect(result.context.products, isEmpty);
      expect(result.context.ticketsEnabled, isFalse);
      expect(result.context.occasionTitle, 'Ples');
    },
  );
  test('unit templates never query an unrelated occasion', () async {
    var called = false;
    final result = await loadEmailPreviewContext(
      null,
      loadForms: (_) async => [],
      loadProducts: (_) async {
        called = true;
        return bundle([]);
      },
    );
    expect(called, isFalse);
    expect(result.unavailable, isFalse);
    expect(result.context.products, isEmpty);
  });
  test(
    'empty or exclusively free catalog uses coherent model financial examples',
    () async {
      final result = await loadEmailPreviewContext(
        OccasionModel(
          isOpen: true,
          isHidden: false,
          isPromoted: false,
          id: 42,
          title: 'Volný vstup',
          link: 'free',
        ),
        loadForms: (_) async => [],
        loadProducts: (_) async =>
            bundle([ProductModel(id: 1, title: 'Zdarma', price: 0)]),
      );
      expect(result.context.products, isEmpty);
      expect(result.unavailable, isFalse);
    },
  );
}
