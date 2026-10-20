import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/last_administration_context.dart';

void main() {
  late Map<String, String> disk;
  LastAdministrationContext open() => LastAdministrationContext(
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
        remove: (key) async {
          disk.remove(key);
        },
      );
  setUp(() => disk = {});

  test(
      'last unit/event survives reopening and is isolated by account and tenant',
      () async {
    final context = open();
    await context.remember(3, 'alice', '/unit/5/edit');
    await context.remember(3, 'alice', '/autumn/admin');
    await context.remember(3, 'bob', '/unit/8/edit');
    await context.remember(1, 'alice', '/unit/9/edit');
    final reopened = open();
    expect(await reopened.restore(3, 'alice', canAccess: (_) async => true),
        '/autumn/admin');
    expect(await reopened.restore(3, 'bob', canAccess: (_) async => true),
        '/unit/8/edit');
    expect(await reopened.restore(1, 'alice', canAccess: (_) async => true),
        '/unit/9/edit');
    expect(
        await reopened.restore(3, null, canAccess: (_) async => true), isNull);
    await reopened.remember(3, 'alice', '/unit/6/edit');
    expect(await open().restore(3, 'alice', canAccess: (_) async => true),
        '/unit/6/edit');
  });

  test('revoked/deleted destinations are checked and discarded', () async {
    await open().remember(3, 'alice', '/autumn/reservations');
    final checked = <String>[];
    expect(
        await open().restore(3, 'alice', canAccess: (path) async {
          checked.add(path);
          return false;
        }),
        isNull);
    expect(checked, ['/autumn/reservations']);
    expect(disk, isEmpty);
  });

  test('network errors retain the preference for the next visit', () async {
    await open().remember(3, 'alice', '/unit/5/edit');
    expect(
        await open().restore(3, 'alice',
            canAccess: (_) async => throw Exception('offline')),
        isNull);
    expect(await open().restore(3, 'alice', canAccess: (_) async => true),
        '/unit/5/edit');
  });

  test('corrupt storage cannot produce an external or object destination',
      () async {
    for (final path in [
      'https://example.com',
      '//example.com',
      '/unit/0/edit',
      '/a/../admin',
      '/a/admin?token=x',
      '/a/admin/orders/12'
    ]) {
      disk['last-administration/v1/3/alice'] = path;
      expect(
          await open().restore(3, 'alice',
              canAccess: (_) async => fail('must not load invalid path')),
          isNull);
      expect(disk, isEmpty);
    }
  });

  test('explicit event and checkout links do not restore administration',
      () {
    for (final path in [
      '/autumn/admin',
      '/unit/5/edit',
      '/form/tickets',
      '/autumn/event'
    ]) {
      expect(LastAdministrationContext.canRestoreFor(path), isFalse);
    }
    for (final path in [null, '', '/', '/login']) {
      expect(LastAdministrationContext.canRestoreFor(path), isTrue);
    }
  });

  test('unavailable storage does not interrupt navigation', () async {
    final context = LastAdministrationContext(
      read: (_) async => throw Exception('blocked'),
      write: (_, __) async => throw Exception('full'),
    );
    await context.remember(3, 'alice', '/unit/5/edit');
    expect(await context.restore(3, 'alice', canAccess: (_) async => true),
        isNull);
  });
}
