import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/email_templates.dart';
import 'package:test/test.dart';

void main() {
  test(
    'fresh triggers never activate at an address prefix or its edited middle',
    () {
      for (final text in [
        'jana@',
        'jana.novakova@',
        'jana+akce@',
        'jana+@',
        'jana-novakova@',
        'jana_1@',
        '"jana"@',
        'jana@example.cz',
        'mailto:@name',
        'https://example.invalid/@name',
        'https://example.invalid/(@name',
        '@example.cz',
        '(@example.cz',
        '{{foo@}}',
      ]) {
        expect(
          EmailTemplateRules.canTrigger(text, text.indexOf('@')),
          isFalse,
          reason: text,
        );
      }
      for (final text in [
        '@',
        'hello @nazev',
        '(@nazev',
        '[@nazev',
        '{@nazev',
      ]) {
        expect(
          EmailTemplateRules.canTrigger(text, text.indexOf('@')),
          isTrue,
          reason: text,
        );
      }
      expect(EmailTemplateRules.canTrigger('@', 0, inLink: true), isFalse);
      expect(EmailTemplateRules.canTrigger('@', 0, inCode: true), isFalse);
      expect(EmailTemplateRules.canTrigger('@', 0, composing: true), isFalse);
    },
  );
  test('explicit insertion respects URL/address/token boundaries', () {
    for (final text in [
      'jana@example.cz',
      'https://example.invalid/order',
      'mailto:user',
      '{{name}}',
    ]) {
      expect(
        EmailTemplateRules.canInsert(text, text.length ~/ 2),
        isFalse,
        reason: text,
      );
    }
    expect(EmailTemplateRules.canInsert('hello world', 5), isTrue);
  });
  test('availability and ranking count authored tokens in active field', () {
    final values = [
      'fullOrder',
      'occasionTitle',
      'paymentDetails',
      'orderSymbol',
    ];
    List<String> rank({
      String query = '',
      EmailTargetField field = EmailTargetField.body,
    }) => EmailTemplateRules.rank(
      values,
      definition: EmailTemplateRules.definition,
      label: (code) =>
          {
            'occasionTitle': 'Název akce',
            'fullOrder': 'Přehled objednávky',
          }[code] ??
          code,
      usage: EmailTemplateRules.occurrences('{{fullOrder}}'),
      query: query,
      field: field,
    );
    expect(rank(), [
      'occasionTitle',
      'paymentDetails',
      'orderSymbol',
      'fullOrder',
    ]);
    expect(rank(query: 'prehled'), ['fullOrder']);
    expect(rank(field: EmailTargetField.subject), [
      'occasionTitle',
      'orderSymbol',
    ]);
    expect(EmailTemplateRules.occurrences('{{name}} {{name}} {{unknown}}'), {
      'name': 2,
      'unknown': 1,
    });
    expect(EmailTemplateRules.kindFor('resetLink'), EmailValueKind.url);
  });
  test(
    'used sections stay below repeatable entries even for exact queries',
    () {
      final result = EmailTemplateRules.rank(
        ['fullOrder', 'order_overview_button', 'occasionTitle'],
        definition: EmailTemplateRules.definition,
        label: (code) => code == 'fullOrder' ? 'Order' : 'Order details',
        usage: {'fullOrder': 1, 'order_overview_button': 2, 'occasionTitle': 2},
        query: 'Order',
      );
      expect(result, ['order_overview_button', 'occasionTitle', 'fullOrder']);
      for (final code in [
        'occasionTitle',
        'order_overview_url',
        'order_overview_button',
        'manage_waitlist_button',
        'offer_button',
        'platformLinks',
        'appLinks',
      ]) {
        expect(
          EmailTemplateRules.definition(code).repeatable,
          isTrue,
          reason: code,
        );
      }
      for (final code in [
        'fullOrder',
        'balanceReasoning',
        'paymentDetails',
        'changeOverview',
      ]) {
        expect(
          EmailTemplateRules.definition(code).repeatable,
          isFalse,
          reason: code,
        );
      }
    },
  );
  test('title suggestions are conservative whole-title occurrences', () {
    const title = 'Podzimní slavnost v Zahradě';
    final text = 'Pozvání na $title. $title!';
    final matches = EmailTemplateRules.titleMatches(text, title).toList();
    expect(matches, hasLength(2));
    expect(text.substring(matches.first.start, matches.first.end), title);
    expect(EmailTemplateRules.titleMatches('X${title}Y', title), isEmpty);
    expect(EmailTemplateRules.titleMatches(title, 'Akce'), isEmpty);
    expect(
      EmailTemplateRules.titleMatches('<a title="$title">url</a>', title),
      isEmpty,
    );
  });
  final asset =
      jsonDecode(
            File(
              '../../assets/email_templates/preview_examples.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test(
    'Dart completion matches production TS on shared fixtures, idempotently',
    () {
      for (final fixture in asset['compositionFixtures'] as List) {
        final links = (fixture['requiredLinks'] as List)
            .map(
              (v) => EmailRequiredLink.fromJson(
                Map<String, dynamic>.from(v as Map),
              ),
            )
            .toList();
        final result = completeEmailContent(fixture['html'] as String, links, fixture['wrapperHtml'] as String?);
        expect(result, fixture['expected'], reason: fixture['name'] as String);
        expect(completeEmailContent(result, links), result);
      }
    },
  );
  test('authoring completion preserves slot ownership, duplicates and wrapper padding', () {
    const action = '<a href="https://example.test/order">Order</a>';
    const card = '<section>Card$emailOverviewSlot</section>';
    const scenario = EmailPreviewScenario(templateCode: 'ORDER', scenario: 'test',
        locale: 'cs', tone: 'neutral',
        values: {'fullOrder': card, 'button': action, 'url': 'https://example.test/order'},
        richCodes: {'fullOrder', 'button'},
        requiredLinks: [EmailRequiredLink(url: 'https://example.test/order', html: action)]);
    const body = '{{fullOrder}}<p>Signature</p>{{fullOrder}}';
    final plan = scenario.authoringCompletion(body);
    expect(plan.forToken('fullOrder', 0), '<section>Card$action</section>');
    expect(plan.forToken('fullOrder', 1), '<section>Card</section>');
    expect(plan.trailingHtml, isEmpty);
    expect(scenario.composeHtml(body), '${plan.forToken('fullOrder', 0)}<p>Signature</p>${plan.forToken('fullOrder', 1)}');
    const wrapper = '<body><div style="padding:24px">{{content}}</div></body>';
    expect(scenario.composeHtml('<p>Text</p>', wrapperHtml: wrapper),
        '<body><div style="padding:24px"><p>Text</p></div></body>');
    expect(scenario.authoringCompletion('<p>Text</p>', wrapperHtml: wrapper).trailingHtml, isEmpty);
    for (final explicit in ['{{button}}', '<a href="{{url}}">Custom</a>']) {
      final plan = scenario.authoringCompletion('$body$explicit');
      expect(plan.forToken('fullOrder', 0), '<section>Card</section>');
      expect(plan.trailingHtml, isEmpty);
    }
    final leading = scenario.authoringCompletion(body,
        wrapperHtml: '<body>$emailOverviewSlot{{content}}</body>');
    expect(leading.leadingHtml, action);
    expect(leading.forToken('fullOrder', 0), '<section>Card</section>');
    final trailing = scenario.authoringCompletion('<p>Text</p>',
        wrapperHtml: '<body>{{content}}$emailOverviewSlot</body>');
    expect(trailing.trailingHtml, action);
    expect(scenario.authoringCompletion(body,
        wrapperHtml: '<body>{{content}}$action</body>').forToken('fullOrder', 0), '<section>Card</section>');
  });
  test(
    'composer escapes once by context, never recursively substitutes values',
    () {
      const scenario = EmailPreviewScenario(
        templateCode: 'test',
        scenario: 'standard',
        locale: 'cs',
        tone: 'formal',
        values: {
          'name': 'A & "B" <C> {{other}}',
          'other': 'wrong',
          'apostrophe': "O'Connor",
          'url': 'https://example.invalid/?a=1&b=2',
          'rich': '<strong>800 Kč</strong>',
        },
        richCodes: {'rich'},
        requiredLinks: [],
      );
      expect(
        scenario.composeSubject('{{name}} {{rich}} {{unknown}}'),
        'A & "B" <C> {{other}} {{rich}} {{unknown}}',
      );
      expect(
        scenario.composeHtml("<span title='{{apostrophe}}'>"),
        "<span title='O&#39;Connor'>",
      );
      expect(
        scenario.restrictTo({'url'}).composeSubject('{{name}} {{url}}'),
        '{{name}} https://example.invalid/?a=1&b=2',
      );
      final html = scenario.composeHtml(
        '<p>{{name}} {{rich}}</p><a href="{{url}}" title="{{rich}}">Link</a>',
      );
      expect(
        html,
        contains(
          'A &amp; &quot;B&quot; &lt;C&gt; {{other}} <strong>800 Kč</strong>',
        ),
      );
      expect(html, contains('href="https://example.invalid/?a=1&amp;b=2"'));
      expect(html, contains('title="{{rich}}"'));
      expect(html, isNot(contains('wrong')));
      expect(
        scenario.composeHtml('<{{name}} href={{url}}>'),
        '<{{name}} href={{url}}>',
      );
      expect(
        scenario.composeHtml('<style>.{{name}}{}</style><!-- {{name}} -->'),
        '<style>.{{name}}{}</style><!-- {{name}} -->',
      );
    },
  );
  test('scenario matrix uses real order markup and coherent totals', () {
    final records = (asset['records'] as List)
        .map(
          (v) => EmailPreviewScenario.fromJson(
            Map<String, dynamic>.from(v as Map),
          ),
        )
        .toList();
    expect(records.where((r) => r.templateCode == 'ORDER_OVERVIEW'), isEmpty);
    final unpaid = records.firstWhere(
      (r) =>
          r.templateCode == 'TICKET_ORDER_CONFIRMATION' &&
          r.scenario == 'unpaid',
    );
    expect(
      unpaid.values['fullOrder'],
      contains('jana.novakova@example.invalid'),
    );
    expect(unpaid.values['fullOrder'], contains('450'));
    expect(unpaid.values['fullOrder'], contains('350'));
    expect(unpaid.values['fullOrder'], contains('800'));
    expect(unpaid.values['balanceReasoning'], contains('800'));
    final full = unpaid.composeHtml('{{fullOrder}}');
    expect(RegExp(r'href=').allMatches(full), hasLength(1));
    expect(full, isNot(contains(emailOverviewSlot)));
    final zero = records.firstWhere(
      (r) =>
          r.templateCode == 'TICKET_ORDER_CONFIRMATION' && r.scenario == 'zero',
    );
    expect(zero.values['amount'], startsWith('0'));
    expect(zero.values['fullOrder'], isNot(contains('450')));
  });
  test('preview leaves custom content unchanged without reprocessing customer text', () {
    const scenario = EmailPreviewScenario(
      templateCode: 'test',
      scenario: 'standard',
      locale: 'cs',
      tone: 'formal',
      values: {'name': '{{content}} & Jana'},
      richCodes: {},
      requiredLinks: [
        EmailRequiredLink(
          url: 'https://example.invalid/order',
          html: '<a href="https://example.invalid/order">Current status</a>',
        ),
      ],
    );
    const wrapper =
        '<html><body><main style="padding:24px">{{content}}</main></body></html>';
    expect(
      scenario.composeHtml('<p>{{name}}</p>', wrapperHtml: wrapper),
      '<html><body><main style="padding:24px"><p>{{content}} &amp; Jana</p></main></body></html>',
    );
    expect(
      scenario
          .composeHtml(
            '<a href="https://example.invalid/order">Existing</a>',
            wrapperHtml: wrapper,
          )
          .split('href='),
      hasLength(2),
    );
  });
  test('generated payment examples include the same IBAN rows as delivery', () {
    final records = asset['records'] as List;
    final reminders = records.where(
      (r) => r['templateCode'] == 'TICKET_ORDER_REMINDER',
    );
    expect(reminders, isNotEmpty);
    for (final record in reminders) {
      final values = record['values'] as Map;
      expect(values['iban'], startsWith('CZ00 '));
      expect(values['paymentDetails'], contains('IBAN:'));
      if (record['scenario'] != 'zero') {
        expect(values['balanceReasoning'], contains('IBAN:'));
      }
    }
  });
}
