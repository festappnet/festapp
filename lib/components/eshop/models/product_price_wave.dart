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
          time: DateTime.parse(json['change_time']).toUtc());

  /// Existing queued changes also remain visible as shared terms.
  static List<ProductPriceWave> columns(
      List<ProductPriceWave> waves, List<ProductModel> products) {
    final byTime = {for (final wave in waves) wave.time: wave};
    for (final product in products) {
      for (final time in [
        ...ProductPriceChange.pending(product.priceChanges).map((p) => p.time),
        ...product.visibilityChanges.where((p) => !p.applied).map((p) => p.time)
      ]) {
        byTime.putIfAbsent(time, () => ProductPriceWave(time: time));
      }
    }
    return byTime.values.toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  List<ProductPriceChange> prices(ProductModel product) =>
      ProductPriceChange.pending(product.priceChanges)
          .where((p) => p.time == time)
          .toList();
  List<ProductVisibilityChange> visibility(ProductModel product) =>
      product.visibilityChanges
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
  const ProductVisibilityChange(
      {required this.id,
      required this.revision,
      this.waveId,
      required this.time,
      required this.hidden,
      this.applied = false,
      this.failureCode});
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
          failureCode: json['failure_code']);
}
