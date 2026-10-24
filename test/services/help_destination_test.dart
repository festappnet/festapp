import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/help_destination.dart';

void main() {
  test('help intents resolve only to fixed administration sections', () {
    expect(HelpDestination.parse('/help-action/seating'), 'seating');
    expect(HelpDestination.path('seating', 'ples-2027'),
        '/ples-2027/reservations/blueprint');
    expect(HelpDestination.path('orders', 'ples-2027'),
        '/ples-2027/reservations/orders/current');
    for (final path in [
      null,
      '',
      '/help-action/../admin',
      '/help-action/seating?next=https://other.test',
      'https://other.test/help-action/seating',
      '//other.test/help-action/seating',
      '/help-action/seating#other',
      '/help-action/unknown'
    ]) {
      expect(HelpDestination.parse(path), isNull, reason: '$path');
    }
    expect(HelpDestination.path('seating', '../another'), isNull);
    expect(HelpDestination.path('unknown', 'ples'), isNull);
    expect(HelpDestination.path('forms', null), isNull);
  });
}
