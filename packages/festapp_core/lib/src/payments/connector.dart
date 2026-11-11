/// Browser-facing protocol only. Secrets and financial verification are server-side.
class PaymentConnector {
  const PaymentConnector({
    required this.id,
    String? payPath,
    String? returnPath,
    String? checkoutHost,
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
    this.confirmation = PaymentConfirmation.verifiedProviderObservation,
    this.currencies = const ['CZK', 'EUR', 'PLN', 'USD', 'GBP'],
  }) : _payPath = payPath, _returnPath = returnPath, _checkoutHost = checkoutHost;
  final String id;
  final String? _payPath, _returnPath, _checkoutHost;
  final PaymentConfirmation confirmation;
  final List<String> currencies;
  HostedCheckoutCapability? get hostedCheckout => _payPath == null || _returnPath == null || _checkoutHost == null
      ? null : HostedCheckoutCapability(_payPath, _returnPath, _checkoutHost);
  String get payPath => hostedCheckout?.payPath ?? (throw StateError('payment_hosted_checkout_unavailable'));
  String get returnPath => hostedCheckout?.returnPath ?? (throw StateError('payment_hosted_checkout_unavailable'));
  String get checkoutHost => hostedCheckout?.checkoutHost ?? (throw StateError('payment_hosted_checkout_unavailable'));
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
    if (hostedCheckout == null) throw StateError('payment_hosted_checkout_unavailable');
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

/// The server still authorizes every capability per order/account/currency.
enum PaymentConfirmation { localCommit, bankEvent, verifiedProviderObservation }
class HostedCheckoutCapability {
  const HostedCheckoutCapability(this.payPath, this.returnPath, this.checkoutHost);
  final String payPath, returnPath, checkoutHost;
}
