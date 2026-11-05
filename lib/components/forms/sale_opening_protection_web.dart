import 'dart:js_interop';

@JS('FestappSaleOpeningProtection.verify')
external JSPromise<JSString> _verify(
  JSString siteKey,
  JSString formLink,
  JSString email,
);

Future<String> verifySaleOpeningVisitor(
  String siteKey,
  String formLink,
  String email,
) async =>
    (await _verify(siteKey.toJS, formLink.toJS, email.toJS).toDart).toDart;
