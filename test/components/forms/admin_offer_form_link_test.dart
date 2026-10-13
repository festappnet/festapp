import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/services/admin_offer_form_link.dart';

void main() {
  const offerId = '12345678-1234-1234-1234-123456789abc';
  test(
      'admin link uses public web form and scoped offer ID without credentials',
      () {
    final uri =
        AdminOfferFormLink.url(formLink: 'festival test', offerId: offerId);
    expect(uri.origin, Uri.parse(AppConfig.webLink).origin);
    expect(uri.pathSegments, ['form', 'festival test']);
    final params =
        Uri.splitQueryString(uri.fragment.substring('waitlist?'.length));
    expect(params, {'offer_id': offerId, 'admin': '1'});
    expect(uri.query, isEmpty);
  });
  test('malformed or absent offer identity cannot open a form', () {
    expect(() => AdminOfferFormLink.url(formLink: '', offerId: offerId),
        throwsArgumentError);
    expect(
        () => AdminOfferFormLink.url(
            formLink: 'festival', offerId: 'bad#token=x'),
        throwsArgumentError);
  });
  test('missing form link reports failure without opening a browser', () async {
    expect(await AdminOfferFormLink.open(formLink: null, offerId: offerId),
        isFalse);
  });
}
