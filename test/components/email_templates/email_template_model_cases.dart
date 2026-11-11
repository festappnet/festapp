import '../../support/fixtures/localization_log_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:festapp_core/email_templates.dart';

void main() {
  test(
    'every template adapts the shared variable catalog without missing entries',
    () {
      final definitions = EmailTemplateModel.substitutionDefinitions;
      expect(definitions.keys, unorderedEquals(emailTemplateVariables.keys));
      for (final template in emailTemplateVariables.entries) {
        expect(
          definitions[template.key]!.map((sub) => sub.code),
          template.value,
        );
        for (final sub in definitions[template.key]!) {
          expect(sub.description, isNotEmpty);
          expect(sub.kind, emailVariableKinds[sub.code]);
        }
      }
      final order = EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION')
          .substitutions;
      final waitlist = EmailTemplateModel(code: 'waitlist_confirmation')
          .substitutions;
      expect(
        order.where((sub) => sub.code == 'orderSymbol').single.description,
        waitlist.where((sub) => sub.code == 'orderSymbol').single.description,
      );
    },
  );
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('application links template exposes only appLinks', () {
    final usage = EmailTemplateModel(code: 'APP_LINKS').getUsageDetails();
    final substitutions = usage['subs'] as List<EmailTemplateSub>;

    expect(substitutions.map((substitution) => substitution.code), [
      'appLinks',
    ]);
  });

  test('account deletion templates have named usage details', () {
    final confirmation = EmailTemplateModel(code: 'ACCOUNT_DELETION_CONFIRM')
        .getUsageDetails();
    final completion = EmailTemplateModel(code: 'ACCOUNT_DELETION_COMPLETE')
        .getUsageDetails();

    expect(confirmation['title'], isNot('Unknown Template'));
    expect(
      (confirmation['subs'] as List<EmailTemplateSub>).map(
        (substitution) => substitution.code,
      ),
      ['appName', 'confirmationUrl', 'expiresAt'],
    );
    expect(completion['title'], isNot('Unknown Template'));
    expect(
      (completion['subs'] as List<EmailTemplateSub>).map(
        (substitution) => substitution.code,
      ),
      ['appName'],
    );
  });

  test(
    'unrecognized template displays its code instead of Unknown Template',
    () {
      final usage = EmailTemplateModel(code: 'CUSTOM_NOTICE').getUsageDetails();

      expect(usage['title'], 'CUSTOM_NOTICE');
    },
  );
}
