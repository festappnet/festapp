import 'package:festapp_core/payments.dart';
import 'package:fstapp/components/stripe_payments/stripe_feature.dart';

/// Provider-owned authoring policy. Customer payment flows use the core registry.
class PaymentEditorConnector {
  const PaymentEditorConnector({
    required this.connector,
    required this.visible,
    required this.canManage,
    required this.supportedCurrencies,
    required this.name,
    required this.settingsPath,
    this.dashboardHost,
  });
  final PaymentConnector connector;
  final bool Function() visible, canManage;
  final Set<String> supportedCurrencies;
  final String name;
  final String? dashboardHost;
  final String Function(int unit) settingsPath;
}

// Composition root for installed provider management UIs.
final paymentEditors = <PaymentEditorConnector>[
  PaymentEditorConnector(
    connector: stripePaymentConnector,
    visible: () => StripeFeature.visible,
    canManage: () => StripeFeature.canManage,
    supportedCurrencies: const {'CZK', 'EUR', 'PLN', 'USD', 'GBP'},
    name: 'Stripe',
    settingsPath: (unit) => '/unit/$unit/edit/card-payments',
    dashboardHost: 'dashboard.stripe.com',
  ),
];

Iterable<PaymentEditorConnector> get managedPaymentEditors => paymentEditors
    .where((provider) => provider.visible() && provider.canManage());
