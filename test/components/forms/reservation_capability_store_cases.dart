import 'package:sembast/sembast_memory.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/reservation_capability_store.dart';

void main() {
  late Map<String, String> rows;
  final clock = DateTime.utc(2026, 10, 20);
  ReservationCapabilityStore store(
          {String backend = 'backend', String form = 'form'}) =>
      ReservationCapabilityStore(
        backend: backend,
        formKey: form,
        now: () => clock,
        read: (key) async => rows[key],
        compareAndSet: (key, expected, next) async {
          if (rows[key] != expected) return false;
          if (next == null) {
            rows.remove(key);
          } else {
            rows[key] = next;
          }
          return true;
        },
      );
  setUp(() => rows = {});
  test(
      'atomic reservation capability writes have one winner and late clear preserves it',
      () async {
    final database =
        await databaseFactoryMemory.openDatabase('reservation-capability.db');
    addTearDown(database.close);
    final results = await Future.wait([
      StorageHelper.compareAndSetString('capability', null, 'first',
          database: database),
      StorageHelper.compareAndSetString('capability', null, 'second',
          database: database),
    ]);
    expect(results.where((won) => won), hasLength(1));
    final winner = results.first ? 'first' : 'second';
    final loser = results.first ? 'second' : 'first';
    expect(
        await StorageHelper.compareAndSetString('capability', loser, null,
            database: database),
        isFalse);
    expect(
        await StorageHelper.compareAndSetString(
            'capability', winner, 'confirmed',
            database: database),
        isTrue);
    expect(
        await StorageHelper.compareAndSetString('capability', winner, null,
            database: database),
        isFalse);
    expect(
        await StorageHelper.compareAndSetString('capability', 'confirmed', null,
            database: database),
        isTrue);
  });
  test(
      'reservation capability restores unknown expiry without seat state and isolates backend/form',
      () async {
    final first = store();
    expect(await first.restore(), isNull);
    final capability = await first.remember('buyer', null);
    final restored = await store().restore();
    expect(restored!.secret, 'buyer');
    expect(restored.expiresAt, isNull);
    expect(restored.generation, capability!.generation);
    expect(capability.encoded.contains('seat'), isFalse);
    expect(await store(backend: 'other').restore(), isNull);
    expect(await store(form: 'other').restore(), isNull);
  });
  test(
      'reservation capability clears expired deadline and preserves newer generation on late completion',
      () async {
    final first = store();
    await first.restore();
    await first.remember('expired', clock.subtract(const Duration(seconds: 1)));
    final next = store();
    expect(await next.restore(), isNull);
    expect(rows, isEmpty);
    final submitted = await next.remember('buyer', null);
    final confirmed =
        await next.remember('buyer', clock.add(const Duration(minutes: 3)));
    expect(await next.clear(submitted), isFalse);
    expect(await first.remember('obsolete', null), isNull);
    expect((await store().restore())!.generation, confirmed!.generation);
    expect(await next.clear(confirmed), isTrue);
    expect(rows, isEmpty);
  });
  test('reservation capability storage failure leaves in-memory caller usable',
      () async {
    final blocked = ReservationCapabilityStore(
      backend: 'backend',
      formKey: 'form',
      read: (_) async => throw StateError('blocked'),
      compareAndSet: (_, __, ___) async => throw StateError('blocked'),
    );
    expect(await blocked.restore(), isNull);
    expect(await blocked.remember('buyer', null), isNull);
    expect(
        await blocked
            .clear(const ReservationCapability('buyer', null, 'generation')),
        isFalse);
  });
}
