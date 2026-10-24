import 'package:test/test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

ProductPriceChange change(
  int id,
  int days, {
  bool applied = false,
  String? failure,
}) => ProductPriceChange(
  id: id,
  revision: 1,
  price: 450 + id * 50,
  time: DateTime.now().toUtc().add(Duration(days: days)),
  applied: applied,
  failureCode: failure,
);
ProductModel product(List<ProductPriceChange> changes) => ProductModel(
  id: 1,
  title: 'Vstupenka',
  price: 450,
  currencyCode: 'CZK',
  priceChanges: changes,
);
void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('new wave proposes a calendar month bounded by terms and event end', () {
    final now = DateTime(2027,1,31,18,17);
    DateTime? suggest(DateTime? end, [List<DateTime> terms=const []]) =>
      ProductPriceWave.suggestTime(now: now,end: end,terms: terms)?.toLocal();
    expect(suggest(DateTime(2027,4,1)),DateTime(2027,2,28,18,17));
    expect(suggest(DateTime(2027,2,3,20)),DateTime(2027,2,3,19,59));
    expect(suggest(DateTime(2027,4,1),[DateTime(2027,3,1,12)]),DateTime(2027,3,1,12,1));
    expect(suggest(null),isNull);
    expect(suggest(DateTime(2027,1,31,18,18)),isNull);
    expect(suggest(DateTime(2027,4,1),[DateTime(2027,4,1)]),isNull);
  });
  test(
    'DST gap rejected, overlap offers both instants and preserves occasion timezone',
    () {
      final prague = tz.getLocation('Europe/Prague');
      expect(
        ProductPriceChange.instants(DateTime.utc(2027, 3, 28, 2, 30), prague),
        isEmpty,
      );
      final overlap = ProductPriceChange.instants(
        DateTime.utc(2026, 10, 25, 2, 30),
        prague,
      );
      expect(overlap, [
        DateTime.utc(2026, 10, 25, 0, 30),
        DateTime.utc(2026, 10, 25, 1, 30),
      ]);
      expect(
        ProductPriceChange.instants(DateTime.utc(2026, 10, 15, 9), prague),
        [DateTime.utc(2026, 10, 15, 7)],
      );
    },
  );
  test('only pending plans sorted, metadata never sent by generic save', () {
    var p = product([change(3, 3), change(1, 1), change(2, 2, applied: true)]);
    expect(ProductPriceChange.pending(p.priceChanges).map((c) => c.id), [1, 3]);
    expect(p.toJson().containsKey('price_changes'), false);
    expect(p.copyWith(price: 500).priceChanges.length, 3);
  });
  test(
    'waves project existing price/visibility targets without changing write payloads',
    () {
      final instant = DateTime.utc(2090, 10, 15, 7);
      var p = product([
        ProductPriceChange(id: 1, revision: 1, price: 500, time: instant),
      ]);
      p = p.copyWith(
        visibilityChanges: [
          ProductVisibilityChange(
            id: 2,
            revision: 1,
            time: instant,
            hidden: true,
          ),
        ],
      );
      final waves = ProductPriceWave.columns(
        [
          ProductPriceWave(id: 3, time: instant),
          ProductPriceWave(id: 4, time: instant.add(const Duration(days: 1))),
        ],
        [p],
      );
      expect(waves.length, 2);
      expect(waves.first.prices(p).single.price, 500);
      expect(waves.first.visibility(p).single.hidden, isTrue);
      expect(p.copyWith(price: 550).visibilityChanges.single.id, 2);
      expect(p.toJson().containsKey('visibility_changes'), isFalse);
    },
  );
}
