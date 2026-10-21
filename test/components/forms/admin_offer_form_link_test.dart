import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/services/admin_offer_form_link.dart';

void main() {
  test('admin offer uses standalone order route without a form slug', () {
    const id = '12345678-1234-1234-1234-123456789abc';
    final uri = AdminOfferFormLink.url(offerId: id);
    expect(uri.origin, Uri.parse(AppConfig.webLink).origin);
    expect(uri.path, '/order');
    expect(uri.fragment, isEmpty);
    expect(uri.queryParameters, {
      'offer_id': id,
      'admin': '1',
      'waitlist': '1',
    });
  });
  test(
    'invalid offer identity is rejected',
    () => expect(
      () => AdminOfferFormLink.url(offerId: 'bad#token=x'),
      throwsArgumentError,
    ),
  );
}
