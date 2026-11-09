import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/email_templates.dart';
import 'package:test/test.dart';

void main() {
  test(
    'retired source is rejected while inserted customer data stays literal',
    () {
      const scenario = EmailPreviewScenario(
        templateCode: 'TICKET_ORDER_CONFIRMATION',
        scenario: 'standard',
        locale: 'cs',
        tone: 'formal',
        values: {'occasionTitle': '{{order_symbol}}'},
        richCodes: {},
        requiredLinks: [],
      );
      expect(
        () => scenario.composeSubject('{{order_symbol}}'),
        throwsStateError,
      );
      expect(
        () => scenario.composeHtml('<p>{{ occasion_title }}</p>'),
        throwsStateError,
      );
      expect(
        () => scenario.composeHtml(
          '<p>Text</p>',
          wrapperHtml: '{{occasion_title}} {{content}}',
        ),
        throwsStateError,
      );
      expect(scenario.composeSubject('{{occasionTitle}}'), '{{order_symbol}}');
      expect(
        scenario.composeHtml('<p>{{occasionTitle}}</p>'),
        '<p>{{order_symbol}}</p>',
      );
    },
  );
  final cases =
      jsonDecode(
            File(
              '../festapp_contracts/email-composition-cases.json',
            ).readAsStringSync(),
          )
          as List;
  for (final c in cases) {
    test('shared delivery/preview composition: ${c['name']}', () {
      final values = Map<String, String>.from(c['values'] as Map);
      final scenario = EmailPreviewScenario(
        templateCode: 'TICKET_ORDER_CONFIRMATION',
        scenario: 'standard',
        locale: 'cs',
        tone: 'formal',
        values: values,
        richCodes: htmlEmailVariables.intersection(values.keys.toSet()),
        requiredLinks: [],
      );
      expect(scenario.composeSubject(c['subject']), c['expectedSubject']);
      expect(scenario.composeHtml(c['html']), c['expectedHtml']);
    });
  }
}
