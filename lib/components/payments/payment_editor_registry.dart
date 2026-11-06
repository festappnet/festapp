import 'package:festapp_core/payments.dart';
import 'package:fstapp/components/stripe_payments/stripe_feature.dart';

/// Provider-owned authoring policy. Customer payment flows use the core registry.
class PaymentEditorConnector {
  const PaymentEditorConnector({
    required this.connector,
    required this.visible,
    required this.canManage,
    required this.supportedCurrencies,
    required this.titleKey,
    required this.setupKey,
    required this.settingsPath,
    this.legacyConnectionField,
    this.restrictedReason = 'unavailable',
  });
  final PaymentConnector connector;
  final bool Function() visible, canManage;
  final Set<String> supportedCurrencies;
  final String titleKey, setupKey, restrictedReason;
  final String Function(int unit) settingsPath;
  final String? legacyConnectionField;

  String? connectionId(Map payments) =>
      (payments['providerConnections'] as Map?)?[connector.id] as String? ??
      (legacyConnectionField == null ? null : payments[legacyConnectionField])
          as String?;
}

// Composition root for installed provider management UIs.
final paymentEditors = <PaymentEditorConnector>[
  PaymentEditorConnector(
    connector: stripePaymentConnector,
    visible: () => StripeFeature.visible,
    canManage: () => StripeFeature.canManage,
    supportedCurrencies: const {'CZK', 'EUR', 'PLN', 'USD', 'GBP'},
    titleKey: 'stripe',
    setupKey: 'setupStripe',
    settingsPath: (unit) => '/unit/$unit/edit/card-payments',
    legacyConnectionField: 'stripeConnectionId',
    restrictedReason: 'stripe_restricted',
  ),
];
