import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('__festappSaleOpeningLink')
external JSString? get _captured;
@JS('__festappSaleOpeningLink')
external set _captured(JSString? value);
Map<String, String>? consumeSaleOpeningLocation() {
  final saved = _captured?.toDart;
  _captured = null;
  if (saved != null) return (jsonDecode(saved) as Map).cast<String, String>();
  // Later same-page navigations have the same memory-only consumption contract.
  if (!web.window.location.hash.contains('sale_opening')) return null;
  final meta = web.document.createElement('meta') as web.HTMLMetaElement;
  meta.name = 'referrer';
  meta.content = 'no-referrer';
  web.document.head?.append(meta);
  final fragment = web.window.location.hash.replaceFirst('#', '');
  web.window.history.replaceState(
    null,
    '',
    '${web.window.location.pathname}${web.window.location.search}',
  );
  try {
    final params = Uri.splitQueryString(fragment);
    final operation = params['sale_opening'], token = params['token'];
    if (operation != 'unsubscribe' ||
        token == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token))
      return {'operation': 'invalid'};
    return {'operation': operation!, 'token': token};
  } on FormatException {
    return {'operation': 'invalid'};
  }
}
