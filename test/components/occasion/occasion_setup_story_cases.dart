import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story.dart';

void main() {
  for (final appSupported in [true, false]) {
    group('story appSupported=$appSupported', () {
      test(
        'dates share a question; presentation and conditional app link follow',
        () {
          final basics = OccasionSetupStory.questions(appSupported)
              .where((q) => q.step == 1)
              .map((q) => q.key);
          expect(
            basics,
            appSupported
                ? ['name', 'dates', 'presentation', 'link', 'promotion']
                : ['name', 'dates', 'promotion'],
          );
        },
      );
      test('every question resumes at its saved position', () {
        final pages = OccasionSetupStory.questions(appSupported);
        for (var i = 0; i < pages.length; i++) {
          expect(
            OccasionSetupStory.index({
              'step': pages[i].step,
              'storyQuestion': pages[i].key,
            }, appSupported),
            i,
          );
        }
      });
      test(
        'legacy review resumes at review and stale question uses target step',
        () {
          final pages = OccasionSetupStory.questions(appSupported);
          expect(
            OccasionSetupStory.index({'step': 5}, appSupported),
            pages.length - 1,
          );
          expect(
            pages[OccasionSetupStory.index({
              'step': 1,
              'storyQuestion': 'review',
            }, appSupported)]
                .key,
            'name',
          );
        },
      );
      test('old date questions resume at the combined date question', () {
        final pages = OccasionSetupStory.questions(appSupported);
        for (final key in ['start', 'end']) {
          expect(
            pages[OccasionSetupStory.index({
              'step': 1,
              'storyQuestion': key,
            }, appSupported)]
                .key,
            'dates',
          );
        }
      });
      test(
        'verified organizer skips verification without moving other questions',
        () {
          final pages = OccasionSetupStory.questions(
            appSupported,
            organizationVerified: true,
          );
          expect(pages.any((q) => q.key == 'verification'), isFalse);
          for (final question in pages) {
            final index = OccasionSetupStory.index(
              {'step': question.step, 'storyQuestion': question.key},
              appSupported,
              organizationVerified: true,
            );
            expect(pages[index].key, question.key);
          }
          expect(
            pages[OccasionSetupStory.index(
              {'step': 5, 'storyQuestion': 'verification'},
              appSupported,
              organizationVerified: true,
            )]
                .key,
            'review',
          );
        },
      );
      test(
        'optional verification does not introduce a required persisted step',
        () {
          final pages = OccasionSetupStory.questions(appSupported);
          expect(pages.where((q) => q.optional).map((q) => q.key), [
            'team',
            'verification',
          ]);
          expect(pages.last.key, 'review');
          expect(
            pages.where((q) => !q.optional).map((q) => q.step).toSet(),
            appSupported ? {1, 2, 3, 4, 5} : {1, 2, 3, 4, 5, 6},
          );
        },
      );
    });
  }
  Map<String, dynamic> formData({
    bool enabled = true,
    bool tickets = true,
    num price = 100,
    bool hiddenProduct = false,
    bool hiddenField = false,
  }) =>
      {
        'formEnabled': enabled,
        'formDraft': {
          'fields': [
            if (tickets) {'type': 'ticket', 'is_hidden': hiddenField},
            {
              'type': 'product',
              'is_hidden': hiddenField,
              'product_type_data': {
                'products': [
                  {'price': price, 'is_hidden': hiddenProduct},
                ],
              },
            },
          ],
        },
      };

  test('team invitations are optional for every journey', () {
    for (final appSupported in [false, true]) {
      final pages = OccasionSetupStory.questions(
        appSupported,
        data: {'formEnabled': false},
        organizationVerified: true,
      );
      final index = pages.indexWhere((q) => q.key == 'team');
      expect(index, greaterThan(0));
      expect(pages[index].optional, isTrue);
      expect(OccasionSetupStory.completesRequiredStep(pages, index), isFalse);
      expect(pages.last.key, 'review');
    }
  });

  test('dependent questions follow paid products and actual ticket field', () {
    List<String> keys(Map<String, dynamic> data) =>
        OccasionSetupStory.questions(
          false,
          data: data,
        ).map((q) => q.key).toList();
    expect(
      keys(formData()),
      containsAll(['form', 'pricing', 'payments', 'appearance']),
    );
    expect(keys(formData(price: 0)), isNot(contains('pricing')));
    expect(keys(formData(price: 0)), isNot(contains('payments')));
    expect(keys(formData(price: 0)), contains('appearance'));
    expect(keys(formData(tickets: false)), contains('ticket'));
    expect(keys(formData(tickets: false)), contains('pricing'));
    expect(keys(formData(hiddenProduct: true)), isNot(contains('payments')));
    expect(keys(formData(hiddenField: true)), contains('ticket'));
    expect(
      keys(formData(enabled: false)),
      isNot(
        anyOf(
          contains('form'),
          contains('pricing'),
          contains('blueprint'),
          contains('payments'),
          contains('ticket'),
        ),
      ),
    );
  });

  test(
    'dependent steps exclude dormant setup without changing persisted IDs',
    () {
      expect(
        OccasionSetupStory.applicableSteps(formData(enabled: false), false),
        {1, 2, 5},
      );
      expect(
        OccasionSetupStory.applicableSteps(formData(enabled: false), true),
        {1, 2, 5},
      );
      expect(OccasionSetupStory.applicableSteps(formData(price: 0), false), {
        1,
        2,
        3,
        5,
        6,
      });
      final paid = formData();
      final pages = OccasionSetupStory.questions(false, data: paid);
      for (final question in pages) {
        expect(
          pages[OccasionSetupStory.index({
            ...paid,
            'step': question.step,
            'storyQuestion': question.key,
          }, false)]
              .key,
          question.key,
        );
      }
    },
  );

  test('inactive payments resume at the next applicable question', () {
    final data = {
      ...formData(price: 0),
      'step': 4,
      'storyQuestion': 'payments',
    };
    final pages = OccasionSetupStory.questions(false, data: data);
    expect(pages[OccasionSetupStory.index(data, false)].key, 'communication');
  });

  test(
    'active price waves require future dates and existing product targets',
    () {
      final data = formData();
      final field = ((data['formDraft'] as Map)['fields'] as List).last as Map;
      ((field['product_type_data'] as Map)['products'] as List).first['id'] =
          -7;
      final now = DateTime.utc(2026, 10, 19);
      data['priceWavesEnabled'] = true;
      expect(OccasionSetupStory.pricingIssueKeys(data, now), {
        'pricingIncomplete',
      });
      data['priceWaves'] = [
        {
          'change_time': '2026-10-20T12:00:00Z',
          'targets': [
            {'product': -7, 'price': 120},
          ],
        },
      ];
      expect(OccasionSetupStory.pricingIssueKeys(data, now), isEmpty);
      final wave = (data['priceWaves'] as List).first as Map;
      wave['change_time'] = '2026-10-18T12:00:00Z';
      (wave['targets'] as List).first['product'] = -99;
      expect(OccasionSetupStory.pricingIssueKeys(data, now), {
        'pricingExpired',
        'pricingMissingProduct',
      });
      data['formEnabled'] = false;
      expect(OccasionSetupStory.pricingIssueKeys(data, now), isEmpty);
    },
  );

  test('scanner is absent and old questions resume safely', () {
    final configured = {...formData(), 'configureScanning': true};
    final pages = OccasionSetupStory.questions(false, data: configured);
    expect(pages.any((q) => q.key == 'scanner'), isFalse);
    final restored = OccasionSetupStory.index(
        {...configured, 'step': 2, 'storyQuestion': 'scanner'}, false);
    expect(pages[restored].key, 'team');
    final presentation = OccasionSetupStory.index(
        {...configured, 'step': 1, 'storyQuestion': 'presentation'}, false);
    expect(pages[presentation].key, 'form');
  });

  test(
    'paid app events have a dedicated payments question before blueprint',
    () {
      final pages = OccasionSetupStory.questions(true, data: formData());
      final payments = pages.indexWhere((q) => q.key == 'payments');
      expect(payments, greaterThan(pages.indexWhere((q) => q.key == 'form')));
      expect(pages[payments].step, 3);
      expect(pages[payments + 1].key, 'paymentTiming');
      expect(pages[pages.length - 2].key, 'promotion');
      expect(
        OccasionSetupStory.completesRequiredStep(pages, payments - 1),
        isFalse,
      );
      expect(
        OccasionSetupStory.completesRequiredStep(pages, payments),
        isFalse,
      );
      expect(
        OccasionSetupStory.completesRequiredStep(pages, payments + 2),
        isTrue,
      );
      expect(
        OccasionSetupStory.questions(
          true,
          data: formData(price: 0),
        ).any((q) => q.key == 'payments'),
        isFalse,
      );
    },
  );

  test(
    'payment readiness requires a verified account and derives currency context',
    () {
      expect(OccasionSetupStory.paymentAccountReady({}), isFalse);
      expect(
        OccasionSetupStory.paymentAccountReady({'bankAccountId': 7}),
        isFalse,
      );
      expect(
        OccasionSetupStory.paymentAccountReady({
          'bankAccountFingerprint': 'verified',
        }),
        isFalse,
      );
      expect(
        OccasionSetupStory.paymentAccountReady({
          'bankAccountId': 7,
          'bankAccountFingerprint': 'verified',
        }),
        isTrue,
      );
      final data = formData();
      expect(OccasionSetupStory.paymentCurrencies(data), {'CZK'});
      final product = (((data['formDraft'] as Map)['fields'] as List)
              .last['product_type_data']['products'] as List)
          .first as Map;
      product['currency_code'] = 'eur';
      expect(OccasionSetupStory.paymentCurrencies(data), {'EUR'});
      product['price'] = 0;
      expect(OccasionSetupStory.paymentCurrencies(data), isEmpty);
    },
  );

  test(
    'communication applies to free forms and completes the shared form step',
    () {
      for (final supported in [false, true]) {
        final pages = OccasionSetupStory.questions(supported, data: formData());
        final communication = pages.indexWhere((q) => q.key == 'communication');
        expect(pages[communication].step, 3);
        expect(pages[communication - 1].key, 'paymentTiming');
        expect(pages[communication + 1].key, 'blueprint');
        final form = pages.indexWhere((q) => q.key == 'form');
        final pricing = pages.indexWhere((q) => q.key == 'pricing');
        expect(OccasionSetupStory.completesRequiredStep(pages, form), isFalse);
        expect(
          OccasionSetupStory.completesRequiredStep(pages, pricing),
          isFalse,
        );
        expect(
          OccasionSetupStory.completesRequiredStep(pages, communication),
          isTrue,
        );
        final free = OccasionSetupStory.questions(
          supported,
          data: formData(price: 0),
        );
        expect(free.any((q) => q.key == 'communication'), isTrue);
        expect(free.any((q) => q.key == 'payments'), isFalse);
        expect(
          OccasionSetupStory.questions(
            supported,
            data: formData(enabled: false),
          ).any((q) => q.key == 'communication'),
          isFalse,
        );
      }
    },
  );

  test(
    'completed active questions reach 100% after explicit review',
    () {
      final draft = OccasionSetupDraft.fromJson({
        'id': 'draft',
        'unit': 1,
        'revision': 1,
        'current_step': 5,
        'data': {
          'title': 'Ples',
          'completedQuestions':
              OccasionSetupStory.questions(true, data: {'title': 'Ples'})
                  .where((q) => !q.optional)
                  .map((q) => q.key)
                  .toList(),
          'reviewed': true,
          'reviewConfirmed': true,
        },
      });
      expect(draft.progress, 100);
    },
  );
}
