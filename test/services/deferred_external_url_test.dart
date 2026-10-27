import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/deferred_external_url.dart';

class _Window implements ExternalUrlWindow {
  String? url;
  bool closed = false;

  @override
  void navigate(String url) => this.url = url;

  @override
  void close() => closed = true;
}

void main() {
  test(
    'reserves the tab synchronously before requesting the overview URL',
    () async {
      final response = Completer<String>();
      final window = _Window();
      var opened = false;
      final result = openDeferredExternalUrl(
        () {
          expect(opened, isTrue);
          return response.future;
        },
        () {
          opened = true;
          return window;
        },
      );
      expect(opened, isTrue);
      expect(window.url, isNull);
      response.complete('https://example.invalid/order?token=fixture');
      expect(await result, isTrue);
      expect(window.url, 'https://example.invalid/order?token=fixture');
      expect(window.closed, isFalse);
    },
  );

  test('closes the reserved tab when obtaining access fails', () async {
    final window = _Window();
    final error = StateError('Access denied');
    await expectLater(
      openDeferredExternalUrl(() => Future.error(error), () => window),
      throwsA(same(error)),
    );
    expect(window.closed, isTrue);
    expect(window.url, isNull);
  });

  test('reports a blocked popup without requesting order access', () async {
    var requested = false;
    await expectLater(
      openDeferredExternalUrl(() async {
        requested = true;
        return 'https://example.invalid/order';
      }, () => null),
      throwsStateError,
    );
    expect(requested, isFalse);
  });
}
