import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/google_auth_service.dart';

void main() {
  test('Google continuation retains internal tab and calendar query only', () {
    const target =
        '/event-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10&filter=latest';
    expect(GoogleAuthService.safeReturnPath(target), target);
    for (final path in [
      '//external.invalid',
      'https://external.invalid/a',
      '/a/../b',
      '/%2f%2fexternal',
      '/a?secret=x',
      '/a?access_token=x',
      '/a#login'
    ]) {
      expect(GoogleAuthService.safeReturnPath(path), '/');
    }
  });
  test('post-login admin navigation prefers the managed unit', () {
    final managedUnit = UnitModel(id: 5);

    final destination = RouterService.postLoginAdminUnit([managedUnit]);

    expect(destination?.id, 5);
  });

  test('post-login admin navigation keeps fallback without a managed unit', () {
    expect(RouterService.postLoginAdminUnit([]), isNull);
  });
}
