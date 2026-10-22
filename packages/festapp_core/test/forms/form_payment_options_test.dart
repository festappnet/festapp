import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

const id = '12345678-1234-4234-8234-123456789abc';
Map<String, dynamic> options() => {
  'configured': {'bank': true, 'stripe': true},
  'available': ['stripe', 'bank'],
  'supportedSurfaces': ['web'],
  'recipient': {'connectionId': id, 'name': 'Organizer'},
  'reservationSeconds': 1860,
};
void main() {
  test(
    'A06 legacy defaults to bank; explicit unavailability never falls back',
    () {
      expect(FormPaymentOptions.fromJson(null).availableFor('web'), ['bank']);
      expect(
        FormPaymentOptions.fromJson({
          ...options(),
          'available': [],
        }).availableFor('web'),
        isEmpty,
      );
    },
  );
  test(
    'A06/A20 card needs a verified recipient and explicitly enabled surface',
    () {
      final value = FormPaymentOptions.fromJson(options());
      expect(value.availableFor('web'), ['stripe', 'bank']);
      expect(value.availableFor('embed'), ['bank']);
      expect(value.stripeReasonFor('embed'), 'surface_unverified');
      expect(
        FormPaymentOptions.fromJson({
          ...options(),
          'recipient': null,
        }).availableFor('web'),
        ['bank'],
      );
    },
  );
  test(
    'A06 form availability survives immutable definition copies and cache round trip',
    () {
      final original = FormDefinition.fromJson({
        'payments': options(),
        'data': {
          'payments': {'bankEnabled': true, 'stripeConnectionId': id},
        },
      });
      final changed = original.copyWith(title: 'Edited');
      expect(changed.payments, original.payments);
      expect(
        () => changed.payments!['available'].add('other'),
        throwsUnsupportedError,
      );
      final restored = FormDefinition.fromJson(changed.toJson());
      expect(restored.payments!['recipient']['connectionId'], id);
      expect(restored.data!['payments']['stripeConnectionId'], id);
    },
  );
}
