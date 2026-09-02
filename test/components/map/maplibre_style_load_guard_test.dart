import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/maplibre/maplibre_style_load_guard.dart';

void main() {
  test('reveals the base map even when scene decoration fails', () async {
    final events = <String>[];

    await completeMapLibreStyleLoad(
      revealBaseMap: () => events.add('revealed'),
      decorateStyle: () async {
        events.add('decorating');
        throw StateError('marker registration failed');
      },
      onDecorationError: (error, stackTrace) => events.add('logged'),
      markCameraReady: () => events.add('ready'),
    );

    expect(events, ['revealed', 'decorating', 'logged', 'ready']);
  });
}
