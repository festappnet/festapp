import 'product_model.dart';
import 'product_price_change.dart';

class ProductPriceWave {
  final int? id;
  final int revision;
  final DateTime time;
  const ProductPriceWave({this.id, this.revision = 1, required this.time});
  factory ProductPriceWave.fromJson(Map<String, dynamic> json) =>
      ProductPriceWave(
        id: json['id'],
        revision: json['revision'],
        time: DateTime.parse(json['change_time']).toUtc(),
      );

  /// Minute-precision proposal in the existing scheduler's local wall time.
  static DateTime? suggestTime({required DateTime now, required DateTime? end,
      Iterable<DateTime> terms = const []}) {
    if (end == null) return null;
    final local = now.toLocal();
    final nextMonth = DateTime(local.year, local.month + 1, 1);
    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    final month = DateTime(nextMonth.year, nextMonth.month,
        local.day > lastDay ? lastDay : local.day, local.hour, local.minute);
    var lower = now;
    for (final term in terms) {
      if (term.isAfter(lower)) lower = term;
    }
    final wallLower = lower.toLocal();
    final first = DateTime(wallLower.year, wallLower.month, wallLower.day,
        wallLower.hour, wallLower.minute).add(const Duration(minutes: 1));
    final last = end.toLocal().subtract(const Duration(microseconds: 1));
    final upper = DateTime(last.year, last.month, last.day, last.hour, last.minute);
    if (first.isAfter(upper)) return null;
    if (month.isBefore(first)) return first.toUtc();
    if (month.isAfter(upper)) return upper.toUtc();
    return month.toUtc();
  }

  /// Existing queued changes also remain visible as shared terms.
  static List<ProductPriceWave> columns(
    List<ProductPriceWave> waves,
    List<ProductModel> products,
  ) {
    final byTime = {for (final wave in waves) wave.time: wave};
    for (final product in products) {
      for (final time in [
        ...ProductPriceChange.pending(product.priceChanges).map((p) => p.time),
        ...product.visibilityChanges
            .where((p) => !p.applied)
            .map((p) => p.time),
      ]) {
        byTime.putIfAbsent(time, () => ProductPriceWave(time: time));
      }
    }
    return byTime.values.toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  List<ProductPriceChange> prices(ProductModel product) =>
      ProductPriceChange.pending(
        product.priceChanges,
      ).where((p) => p.time == time).toList();
  List<ProductVisibilityChange> visibility(ProductModel product) => product
      .visibilityChanges
      .where((p) => !p.applied && p.time == time)
      .toList();
}

class ProductVisibilityChange {
  final int id, revision;
  final int? waveId;
  final DateTime time;
  final bool? hidden;
  final bool applied;
  final String? failureCode;
  const ProductVisibilityChange({
    required this.id,
    required this.revision,
    this.waveId,
    required this.time,
    required this.hidden,
    this.applied = false,
    this.failureCode,
  });
  factory ProductVisibilityChange.fromJson(Map<String, dynamic> json) =>
      ProductVisibilityChange(
        id: json['id'],
        revision: json['revision'],
        waveId: json['wave_id'],
        time: DateTime.parse(json['change_time']).toUtc(),
        hidden: json['new_value'] == 'true'
            ? true
            : json['new_value'] == 'false'
            ? false
            : null,
        applied: json['applied'] == true,
        failureCode: json['failure_code'],
      );
}
