import 'dart:js_interop';

@JS('__festappCustomerChangeToken')
external JSString? get _captured;
@JS('__festappCustomerChangeToken')
external set _captured(JSString? value);
String? consumeCustomerChangeToken() {
  final value = _captured?.toDart;
  _captured = null;
  return value;
}
