/// Browser-facing protocol only. Secrets and financial verification are server-side.
class PaymentConnector {
  const PaymentConnector({
    required this.id,
    required this.payPath,
    required this.returnPath,
    required this.checkoutHost,
    this.orderConnectionField = 'payment_connection_id',
    this.unavailableReasonField = 'unavailableReason',
    this.legacyAvailability = false,
    this.labelKey = 'card',
    this.hintKey = 'cardHint',
    this.checkoutPath,
    this.checkoutGuidParameter,
    this.authorizationHost,
    this.authorizationPath,
    this.callbackEndpoint,
  });
  final String id, payPath, returnPath, checkoutHost;
  final String orderConnectionField, unavailableReasonField, labelKey, hintKey;
  final bool legacyAvailability;
  final String? checkoutPath, checkoutGuidParameter;
  final String? authorizationHost, authorizationPath, callbackEndpoint;
  Uri authorizationUri(String value) {
    final uri = Uri.parse(value);
    if (authorizationHost == null ||
        uri.scheme != 'https' ||
        uri.host != authorizationHost ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (authorizationPath != null && uri.path != authorizationPath)) {
      throw StateError('payment_authorization_url_invalid');
    }
    return uri;
  }

  Uri checkoutUri(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host != checkoutHost ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw StateError('payment_checkout_url_invalid');
    }
    if (checkoutPath != null && uri.path.toLowerCase() != checkoutPath) {
      throw StateError('payment_checkout_url_invalid');
    }
    if (checkoutGuidParameter != null &&
        (uri.hasFragment || uri.queryParametersAll.length != 1 ||
         uri.queryParametersAll.entries.single.key.toLowerCase() != checkoutGuidParameter ||
         uri.queryParametersAll.entries.single.value.length != 1 ||
         !RegExp(r'^(?:[a-f0-9]{32}|[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})$', caseSensitive: false)
             .hasMatch(uri.queryParametersAll.entries.single.value.single))) {
      throw StateError('payment_checkout_url_invalid');
    }
    return uri;
  }
}
