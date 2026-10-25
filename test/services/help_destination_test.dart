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
  test('scanner settings retain the selected event and safe return path', () {
    expect(HelpDestination.parse('/help-action/scanner-settings'),
        HelpDestination.scannerSettings);
    expect(HelpDestination.isWebClient('scanner-settings'), isTrue);
    expect(HelpDestination.isWebClient('settings'), isFalse);
    final target = Uri.parse(
        HelpDestination.path('scanner-settings', 'ples-2027', occasionId: 42)!);
    expect(target.path, '/scan/settings');
    expect(target.queryParameters, {
      'occasion': '42',
      'returnTo': '/ples-2027/reservations/tickets',
    });
    for (final id in [null, 0, -1]) {
      expect(HelpDestination.path('scanner-settings', 'ples', occasionId: id),
          isNull);
    }
    expect(HelpDestination.path('scanner-settings', '../other', occasionId: 42),
        isNull);
    expect(HelpDestination.parse('/help-action/scanner-settings?occasion=999'),
        isNull);
  });
}
