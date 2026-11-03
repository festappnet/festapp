@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:venue_seat_picker_example/demo/storage_web.dart';

void main() {
  test('draft larger than localStorage quota survives persistence', () async {
    final payload = 'x' * (6 * 1024 * 1024);
    await Future<void>.sync(() => writeDraft(payload));
    expect(await readDraft(), payload);
    // Latest write wins, including an explicit save after an autosave.
    final first = Future<void>.sync(() => writeDraft('autosave'));
    final second = Future<void>.sync(() => writeDraft('saved baseline'));
    await Future.wait([first, second]);
    expect(await readDraft(), 'saved baseline');
  });

  test(
    'legacy localStorage draft migrates without losing its contents',
    () async {
      // Remove the IndexedDB record through the same browser API used by storage.
      // A fresh database is selected by clearing the store in the test below.
      final request = web.window.indexedDB.deleteDatabase(
        'venue-layout-preview',
      );
      final done = Future<void>(() async {
        while (request.readyState != 'done') {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await done;
      web.window.localStorage.setItem('venue-layout-demo:v1:local', 'legacy');
      expect(await readDraft(), 'legacy');
      expect(
        web.window.localStorage.getItem('venue-layout-demo:v1:local'),
        isNull,
      );
      expect(await readDraft(), 'legacy');
    },
  );
}
