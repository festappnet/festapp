import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';

void main() {
  test('application links template exposes only appLinks', () {
    final usage = EmailTemplateModel(code: 'APP_LINKS').getUsageDetails();
    final substitutions = usage['subs'] as List<EmailTemplateSub>;

    expect(
        substitutions.map((substitution) => substitution.code), ['appLinks']);
  });

  test('account deletion templates have named usage details', () {
    final confirmation =
        EmailTemplateModel(code: 'ACCOUNT_DELETION_CONFIRM').getUsageDetails();
    final completion =
        EmailTemplateModel(code: 'ACCOUNT_DELETION_COMPLETE').getUsageDetails();

    expect(confirmation['title'], isNot('Unknown Template'));
    expect(
      (confirmation['subs'] as List<EmailTemplateSub>)
          .map((substitution) => substitution.code),
      ['appName', 'confirmationUrl', 'expiresAt'],
    );
    expect(completion['title'], isNot('Unknown Template'));
    expect(
      (completion['subs'] as List<EmailTemplateSub>)
          .map((substitution) => substitution.code),
      ['appName'],
    );
  });

  test('unrecognized template displays its code instead of Unknown Template',
      () {
    final usage = EmailTemplateModel(code: 'CUSTOM_NOTICE').getUsageDetails();

    expect(usage['title'], 'CUSTOM_NOTICE');
  });
}
