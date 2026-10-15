import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';

void main() {
  test('SQL blocks every reserved application root for new occasion slugs', () {
    final sql =
        File('database/functions/public_links/registry.sql').readAsStringSync();
    for (final root in AppRouter.getRootLinks()) {
      expect(sql, contains("'$root'"), reason: root);
    }
  });

  test('standalone document paths are not parsed as occasion links', () {
    expect(
      AppRouter.getRootLinks(),
      containsAll(<String>[
        'admin',
        'privacy',
        'terms',
        'support',
        'delete-account',
      ]),
    );
  });
}
