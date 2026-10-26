import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/organizer_destination.dart';

void main() {
  test(
    'creation continuation is exact and carries no resource or return URL',
    () {
      expect(OrganizerDestination.isCreate('/organizer-action/create'), isTrue);
      for (final value in <String?>[
        null,
        '/organizer-action/create?unit=99',
        '/organizer-action/create/',
        '//evil.invalid/organizer-action/create',
        'https://evil.invalid/organizer-action/create',
        '/help-action/settings',
      ]) {
        expect(OrganizerDestination.isCreate(value), isFalse, reason: value);
      }
    },
  );
}
