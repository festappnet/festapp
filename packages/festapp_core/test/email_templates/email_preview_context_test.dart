import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/email_templates.dart';
import 'package:test/test.dart';

void main() {
  final data =
      jsonDecode(
            File(
              '../../assets/email_templates/preview_examples.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final records = (data['records'] as List)
      .map(
        (v) =>
            EmailPreviewScenario.fromJson(Map<String, dynamic>.from(v as Map)),
      )
      .toList();
  test('reminder preview reflects form cancellation and inline payment QR', () {
    final reminder = records.firstWhere(
      (r) => r.templateCode == 'TICKET_ORDER_REMINDER' && r.locale == 'cs',
    );
    const body = '{{balanceReasoning}}{{fullOrder}}<p>Podpis</p>';
    const wrapper = '<main>{{content}}</main>';
    final disabled = reminder.withContext(
      const EmailPreviewContext(inlinePaymentQr: false),
    );
    expect(disabled.composeHtml(body), isNot(contains('požádat o storno')));
    expect(disabled.composeHtml(body), isNot(contains(emailPreviewPaymentQrSource)));
    expect(disabled.composeHtml('{{order_overview_button}}'), isNot(contains('požádat o storno')));
    expect(disabled.composeHtml(body), contains('Zobrazit aktuální stav objednávky'));

    final enabled = reminder.withContext(const EmailPreviewContext(
      cancellationAvailable: true,
    ));
    final completed = enabled.composeHtml(body, wrapperHtml: wrapper);
    expect(completed, contains('požádat o storno'));
    expect(completed, contains('Zaplaťte pomocí QR kódu'));
    expect(completed, contains(emailPreviewPaymentQrSource));
    expect(
      enabled.authoringCompletion(body, wrapperHtml: wrapper)
          .forToken('balanceReasoning', 0),
      contains(emailPreviewPaymentQrSource),
    );
    expect(enabled.authoringCompletion(body).trailingHtml, isEmpty);
    expect(
      enabled.composeHtml('<p>Podpis</p>', wrapperHtml: wrapper),
      endsWith('${enabled.inlinePaymentQrHtml}</main>'),
    );
    final paid = records.firstWhere(
      (r) => r.templateCode == 'TICKET_ORDER_UPDATE' && r.scenario == 'paid',
    ).withContext(const EmailPreviewContext(inlinePaymentQr: true));
    expect(paid.composeHtml(body), isNot(contains(emailPreviewPaymentQrSource)));
  });
  test('single application waitlist examples offer exactly one place', () {
    for (final record in records.where(
      (r) => r.templateCode.startsWith('waitlist'),
    )) {
      final single = record.withContext(
        const EmailPreviewContext(
          ticketsEnabled: false,
          blueprintEnabled: false,
        ),
      );
      expect(single.values['participant_count'], '1');
      expect(single.values['participant_phrase'], '1 osobu');
      expect(single.values['offered_count'], '1');
      expect(single.values['offered_places'], '1 místo');
      if (record.templateCode == 'waitlist_offer') {
        expect(
          single.values['offer_button'],
          isNot(record.values['offer_button']),
        );
        expect(
          single.values['waitlist_offer_instructions'],
          isNot(record.values['waitlist_offer_instructions']),
        );
      }
    }
  });
  test('opening authoring uses application wording from production snapshots', () {
    final opening = records.where((r) => r.templateCode == 'sale_opening_opened');
    expect(opening, isNotEmpty);
    for (final record in opening) {
      final applications = record.withContext(const EmailPreviewContext(
        occasionTitle: 'Letní tábor', ticketsEnabled: false));
      final tickets = record.withContext(const EmailPreviewContext(
        occasionTitle: 'Letní tábor', ticketsEnabled: true));
      expect(applications.values['occasionTitle'], 'Letní tábor');
      for (final code in ['sale_opening_subject', 'sale_opening_heading',
        'sale_opening_action', 'sale_opening_disclaimer']) {
        expect(applications.values[code], isNot(tickets.values[code]));
      }
      expect(applications.values.values.join(), isNot(contains('{{preview_')));
    }
  });
  const context = EmailPreviewContext(
    occasionTitle: 'Ples ve Lhotě',
    deadline: '10. 11. 2026',
    products: [
      EmailPreviewProduct(
        title: 'Místo u stolu',
        typeTitle: 'Vstupenky',
        price: 600,
      ),
      EmailPreviewProduct(
        title: 'Večeře & dezert',
        typeTitle: 'Občerstvení',
        price: 200,
      ),
    ],
  );
  test(
    'order introductions keep tone while binding the current event title',
    () {
      for (final record in records.where(
        (r) => r.values.containsKey('orderCommunication'),
      )) {
        final value = record
            .withContext(
              const EmailPreviewContext(occasionTitle: '<Ples & hosté>'),
            )
            .values['orderCommunication']!;
        if (record.templateCode != 'TICKET_ORDER_REMINDER') {
          expect(value, contains('&lt;Ples &amp; hosté&gt;'));
        }
        expect(value, isNot(contains('{{preview_')));
        if (record.locale == 'cs') {
          expect(
            value,
            contains(record.tone == 'informal' ? 'Ahoj' : 'Dobrý den'),
          );
        }
      }
    },
  );
  test('configured account replaces fixture digits in every payment block', () {
    const account = EmailPreviewPaymentAccount(
      accountNumber: '2102808173/2010',
      iban: 'CZ87 2010 0000 0021 0280 8173',
      currencies: ['CZK'],
    );
    for (final original in records.where(
      (r) => r.values.containsKey('paymentDetails'),
    )) {
      final adjusted = original.withContext(
        context.withPaymentAccount(account),
      );
      final html = adjusted.values['paymentDetails']!;
      final text = html.replaceAll(RegExp(r'<[^>]*>'), '');
      if (original.contextDefaults['preview_payment_method'] != 'bank' ||
          original.contextDefaults['preview_collection_allowed'] != 'true') {
        expect(adjusted.values['accountNumber'], isEmpty);
        expect(adjusted.values['iban'], isEmpty);
        expect(text, isNot(contains(account.accountNumber)));
        continue;
      }
      expect(text, contains(account.accountNumber));
      expect(text, contains(account.iban));
      expect(text, isNot(contains('0000000000/0000')));
      expect(html, isNot(contains('{{preview_')));
      expect(adjusted.values['accountNumber'], account.accountNumber);
    }
  });
  test(
    'context binds actual catalog titles, types and prices into production HTML',
    () {
      final scenario = records
          .firstWhere(
            (s) =>
                s.templateCode == 'TICKET_ORDER_CONFIRMATION' &&
                s.scenario == 'unpaid',
          )
          .withContext(context);
      expect(scenario.values['occasionTitle'], 'Ples ve Lhotě');
      final html = scenario.values['fullOrder']!;
      expect(html, contains('Vstupenky: Místo u stolu'));
      expect(html, contains('Občerstvení: Večeře &amp; dezert'));
      expect(html, contains('600'));
      expect(html, contains('200'));
      expect(html, contains('800'));
      expect(html, contains('jana.novakova@example.com'));
      expect(scenario.values['balanceReasoning'], contains('10. 11. 2026'));
      expect(html, isNot(contains('Dospělý vstup')));
      expect(
        scenario.composeSubject('Objednávka na {{occasionTitle}} - {{amount}}'),
        contains('Ples ve Lhotě'),
      );
    },
  );
  test(
    'occasion ticket mode selects canonical application or ticket markup',
    () {
      for (final original in records.where(
        (s) => s.values.containsKey('fullOrder'),
      )) {
        final application = original.withContext(
          const EmailPreviewContext(ticketsEnabled: false),
        );
        final ticket = original.withContext(
          const EmailPreviewContext(ticketsEnabled: true),
        );
        final label = original.locale == 'cs'
            ? 'Přihláška X3425W8H2U'
            : 'Application X3425W8H2U';
        final ticketLabel = original.locale == 'cs'
            ? 'Vstupenka X3425W8H2U'
            : 'Ticket X3425W8H2U';
        expect(application.values['fullOrder'], contains(label));
        expect(application.values['fullOrder'], isNot(contains(ticketLabel)));
        expect(ticket.values['fullOrder'], contains(ticketLabel));
        expect(application.composeHtml('{{fullOrder}}'), contains(label));
        expect(
          application
              .authoringCompletion('{{fullOrder}}')
              .forToken('fullOrder', 0),
          contains(label),
        );
        final restricted = original
            .restrictTo({'fullOrder'})
            .withContext(const EmailPreviewContext(ticketsEnabled: false));
        expect(restricted.values['fullOrder'], contains(label));
        expect(
          application.restrictTo({'amount'}).applicationContextTemplates,
          isEmpty,
        );
      }
    },
  );
  test(
    'every generated contextual block resolves once with coherent totals',
    () {
      for (final original in records) {
        final scenario = original.withContext(context);
        for (final code in scenario.richCodes) {
          expect(
            scenario.values[code],
            isNot(contains('{{preview_')),
            reason: '${scenario.templateCode}/${scenario.scenario}/$code',
          );
        }
        if (!scenario.templateCode.startsWith('TICKET')) continue;
        expect(
          scenario.values['amount'],
          startsWith(
            scenario.scenario == 'zero'
                ? '0'
                : scenario.templateCode == 'TICKET_ORDER_PAYMENT_DONE' &&
                      scenario.scenario == 'deposit'
                ? '300'
                : '800',
          ),
        );
        if (scenario.scenario == 'zero') {
          expect(scenario.values['fullOrder'], isNot(contains('600')));
        }
      }
    },
  );
  test(
    'context binding preserves exact renderer HTML with original fixture data',
    () {
      const fixture = EmailPreviewContext(
        cancellationAvailable: true,
        products: [
          EmailPreviewProduct(
            title: 'Dospělý vstup',
            typeTitle: 'Vstupné',
            price: 450,
          ),
          EmailPreviewProduct(
            title: 'Studentský vstup',
            typeTitle: 'Vstupné',
            price: 350,
          ),
        ],
      );
      for (final original in records.where(
        (r) => r.templateCode.startsWith('TICKET'),
      )) {
        final adjusted = original.withContext(fixture);
        for (final code in [
          'fullOrder',
          'balanceReasoning',
          'paymentDetails',
          'changeOverview',
        ]) {
          expect(
            adjusted.values[code],
            original.values[code],
            reason: '${original.templateCode}/${original.scenario}/$code',
          );
        }
      }
    },
  );
  test(
    'title-only contexts keep coherent model money and update deadline everywhere',
    () {
      final original = records.firstWhere(
        (r) =>
            r.templateCode == 'TICKET_ORDER_CONFIRMATION' &&
            r.scenario == 'unpaid',
      );
      final adjusted = original.withContext(
        const EmailPreviewContext(
          occasionTitle: 'Tábor v Zahradě',
          deadline: '20. 12. 2026',
        ),
      );
      expect(adjusted.values['fullOrder'], original.values['fullOrder']);
      expect(adjusted.values['deadline'], '20. 12. 2026');
      expect(adjusted.values['balanceReasoning'], contains('20. 12. 2026'));
      expect(
        adjusted.values['balanceReasoning'],
        isNot(contains('{{preview_')),
      );
    },
  );
  test('catalog HTML is escaped and never treated as another binding', () {
    const unusual = EmailPreviewContext(
      products: [
        EmailPreviewProduct(
          title: '<script>{{preview_total}}</script>',
          typeTitle: 'A & B',
          price: 75.50,
          currency: 'EUR',
        ),
      ],
    );
    final adjusted = records
        .firstWhere(
          (r) =>
              r.templateCode == 'TICKET_ORDER_CONFIRMATION' &&
              r.scenario == 'unpaid',
        )
        .withContext(unusual);
    expect(
      adjusted.values['fullOrder'],
      contains('&lt;script&gt;{{preview_total}}&lt;/script&gt;'),
    );
    expect(adjusted.values['fullOrder'], contains('A &amp; B'));
    expect(adjusted.values['amount'], contains('151'));
    expect(adjusted.values['amount'], contains('€'));
    expect(adjusted.withContext(unusual).values, adjusted.values);
    final limited = adjusted.restrictTo({'occasionTitle'});
    expect(limited.values.keys, ['occasionTitle']);
  });
}
