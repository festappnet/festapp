import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/bounded_database_opener.dart';
import 'package:fstapp/services/installation_cutover_service.dart';
import 'package:sembast/sembast.dart';

class _Database extends Fake implements Database {
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  test('never-resolving open rejects all shared callers before transactions',
      () async {
    final pending = Completer<Database>();
    var opens = 0;
    final opener = BoundedDatabaseOpener(
      open: (_) {
        opens++;
        return pending.future;
      },
      timeout: const Duration(milliseconds: 10),
    );
    final first = opener.get('default');
    final second = opener.get('default');
    expect(identical(first, second), isTrue);
    await Future.wait([
      expectLater(first, throwsA(isA<StorageOpenTimeoutException>())),
      expectLater(second, throwsA(isA<StorageOpenTimeoutException>())),
    ]);
    await expectLater(
        opener.get('default'), throwsA(isA<StorageOpenTimeoutException>()));
    expect(opens, 1,
        reason: 'A still-pending failed path must not open concurrently');
    var writes = 0;
    final cutover = InstallationCutoverService(
      generation: 'next',
      read: (_, [path]) async {
        await opener.get(path ?? 'default');
        return null;
      },
      removePrefixes: (_, [path]) async {
        writes++;
      },
      writeAtomic: (_, [path]) async {
        writes++;
      },
    );
    await expectLater(
        cutover.run(), throwsA(isA<StorageOpenTimeoutException>()));
    expect(writes, 0,
        reason: 'Failed open must not launch late migration writes');
  });

  test('late handle closes before another opener can own the path', () async {
    final pending = Completer<Database>();
    final late = _Database();
    final next = _Database();
    var opens = 0;
    final opener = BoundedDatabaseOpener(
      open: (_) {
        opens++;
        return opens == 1 ? pending.future : Future.value(next);
      },
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
        opener.get('default'), throwsA(isA<StorageOpenTimeoutException>()));
    pending.complete(late);
    await Future<void>.delayed(Duration.zero);
    expect(late.closes, 1);
    expect(await opener.get('default'), same(next));
    expect(await opener.get('default'), same(next));
    expect(opens, 2);
    expect(next.closes, 0,
        reason: 'The successful consumer retains its handle');
  });

  test('failed open can retry without swallowing its error', () async {
    var opens = 0;
    final database = _Database();
    final opener = BoundedDatabaseOpener(open: (_) async {
      if (++opens == 1) throw StateError('open failed');
      return database;
    });
    await expectLater(opener.get('default'), throwsStateError);
    expect(await opener.get('default'), same(database));
    expect(opens, 2);
  });
}
