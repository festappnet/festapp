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
      expect(html, contains('jana.novakova@example.invalid'));
      expect(scenario.values['balanceReasoning'], contains('10. 11. 2026'));
      expect(html, isNot(contains('Dospělý vstup')));
      expect(
        scenario.composeSubject('Objednávka na {{occasionTitle}} - {{amount}}'),
        contains('Ples ve Lhotě'),
      );
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
