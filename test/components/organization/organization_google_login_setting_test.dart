import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/organization/organization_model.dart';

void main() {
  test(
      'Google login setting defaults off and round-trips independently of registration',
      () {
    expect(
        OrganizationModel.fromJson({}).isGoogleLoginEnabled ?? false, isFalse);
    final organization = OrganizationModel.fromJson({
      'IS_GOOGLE_LOGIN_ENABLED': true,
      'IS_REGISTRATION_ENABLED': false,
    });
    expect(organization.isGoogleLoginEnabled, isTrue);
    expect(organization.toJson()['IS_GOOGLE_LOGIN_ENABLED'], isTrue);
    expect(organization.toJson()['IS_REGISTRATION_ENABLED'], isFalse);
    organization.isGoogleLoginEnabled = false;
    expect(organization.toJson()['IS_GOOGLE_LOGIN_ENABLED'], isFalse);
  });
}
