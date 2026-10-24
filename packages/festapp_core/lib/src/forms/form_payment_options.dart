/// Server availability is independent from the saved form configuration.
/// An explicit empty list never falls back to bank payment.
class FormPaymentOptions {
  FormPaymentOptions._(
    this.available,
    this.supportedSurfaces,
    this.stripeConnectionId,
    this.recipientName,
    this.reservationSeconds,
    this.stripeConfigured,
    this.unavailableReason,
  );
  final List<String> available;
  final Set<String> supportedSurfaces;
  final String? stripeConnectionId, recipientName, unavailableReason;
  final int reservationSeconds;
  final bool stripeConfigured;
  factory FormPaymentOptions.fromJson(Map<String, dynamic>? value) {
    if (value == null)
      return FormPaymentOptions._(
        const ['bank'],
        const {},
        null,
        null,
        1860,
        false,
        'not_configured',
      );
    final recipient = value['recipient'] is Map
        ? value['recipient'] as Map
        : const {};
    final id = recipient['connectionId'];
    final seconds = value['reservationSeconds'];
    return FormPaymentOptions._(
      List.unmodifiable(
        value['available'] is List
            ? (value['available'] as List)
                  .whereType<String>()
                  .where((x) => x == 'bank' || x == 'stripe')
                  .toSet()
            : const <String>[],
      ),
      Set.unmodifiable(
        value['supportedSurfaces'] is List
            ? (value['supportedSurfaces'] as List).whereType<String>()
            : const <String>[],
      ),
      id is String &&
              RegExp(
                r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
              ).hasMatch(id)
          ? id
          : null,
      recipient['name'] is String ? recipient['name'] : null,
      seconds is int && seconds > 0 && seconds <= 86400 ? seconds : 1860,
      value['configured'] is Map && value['configured']['stripe'] == true,
      value['stripeUnavailableReason'] is String
          ? value['stripeUnavailableReason']
          : null,
    );
  }
  List<String> availableFor(String surface) => List.unmodifiable(
    available.where(
      (method) =>
          method != 'stripe' ||
          (stripeConnectionId != null && supportedSurfaces.contains(surface)),
    ),
  );
  String? stripeReasonFor(String surface) {
    if (availableFor(surface).contains('stripe')) return null;
    if (available.contains('stripe') && !supportedSurfaces.contains(surface))
      return 'surface_unverified';
    return unavailableReason ?? 'recipient_changed';
  }
}
