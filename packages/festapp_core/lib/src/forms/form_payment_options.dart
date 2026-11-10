import '../../payments.dart';

/// Server availability is independent from the saved form configuration.
/// An explicit empty list never falls back to bank payment.
class FormPaymentOptions {
  FormPaymentOptions._(this.available, this.providers, this.reservationSeconds, [this.cashInstructions = '']);
  final List<String> available;
  final Map<String, ProviderPaymentOptions> providers;
  final int reservationSeconds;
  final String cashInstructions;
  bool get cardConfigured => providers.values.any((p) => p.configured);
  // Released Stripe-only accessors are an explicit compatibility adapter.
  String? get connectionId => providers['stripe']?.connectionId;
  String? get recipientName => providers['stripe']?.recipientName;
  String? get unavailableReason => providers['stripe']?.unavailableReason;
  Set<String> get supportedSurfaces => providers['stripe']?.supportedSurfaces ?? const {};
  factory FormPaymentOptions.fromJson(
    Map<String, dynamic>? value, {
    PaymentConnectorRegistry? registry,
  }) {
    registry ??= paymentConnectors;
    if (value == null)
      return FormPaymentOptions._(const ['bank'], const {}, 1860);
    final providers = <String, ProviderPaymentOptions>{};
    for (final connector in registry.hosted) {
      final all = value['providers'];
      final raw = all is Map && all[connector.id] is Map
          ? all[connector.id] as Map
          : all == null && connector.legacyAvailability
          ? value
          : const {};
      final recipient = raw['recipient'] is Map
          ? raw['recipient'] as Map
          : const {};
      final id = recipient['connectionId'];
      providers[connector.id] = ProviderPaymentOptions(
        connectionId:
            id is String &&
                RegExp(
                  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
                ).hasMatch(id)
            ? id
            : null,
        recipientName: recipient['name'] is String
            ? recipient['name'] as String
            : null,
        configured:
            raw['configured'] == true ||
            (raw['configured'] is Map &&
                raw['configured'][connector.id] == true),
        unavailableReason: raw['reason'] is Map
            ? raw['reason']['code'] as String?
            : raw[connector.unavailableReasonField] as String?,
        supportedSurfaces: Set.unmodifiable(
          raw['supportedSurfaces'] is List
              ? (raw['supportedSurfaces'] as List).whereType<String>()
              : const <String>[],
        ),
      );
    }
    final seconds = value['reservationSeconds'];
    return FormPaymentOptions._(
      List.unmodifiable(
        value['available'] is List
            ? (value['available'] as List)
                  .whereType<String>()
                  .where((id) {
                    final connector = registry!.get(id);
                    if (connector == null) return false;
                    if (connector.hostedCheckout == null) {
                      final projected = value[id];
                      return projected is Map ? projected['available'] == true : id == 'bank';
                    }
                    return value['providers'] is! Map ||
                        (value['providers'][id] is Map && value['providers'][id]['available'] == true);
                  })
                  .toSet()
            : const <String>[],
      ),
      Map.unmodifiable(providers),
      seconds is int && seconds > 0 && seconds <= 86400 ? seconds : 1860,
      value['cash'] is Map ? value['cash']['instructions'] as String? ?? '' : '',
    );
  }
  List<String> availableFor(String surface) => List.unmodifiable(
    available.where(
      (method) =>
          !providers.containsKey(method) ||
          (providers[method]?.connectionId != null &&
              providers[method]!.supportedSurfaces.contains(surface)),
    ),
  );
  String? cardReasonFor(String surface) {
    if (availableFor(surface).any(providers.containsKey)) return null;
    if (available.any(
      (id) =>
          providers[id] != null &&
          !providers[id]!.supportedSurfaces.contains(surface),
    ))
      return 'surface_unverified';
    return unavailableReason ?? 'recipient_changed';
  }
}

class ProviderPaymentOptions {
  const ProviderPaymentOptions({
    required this.connectionId,
    required this.recipientName,
    required this.configured,
    required this.unavailableReason,
    required this.supportedSurfaces,
  });
  final String? connectionId, recipientName, unavailableReason;
  final bool configured;
  final Set<String> supportedSurfaces;
}
