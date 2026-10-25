import 'package:festapp_core/time.dart';
import 'package:timezone/timezone.dart' as tz;

class ProductPriceChange {
  final int id;
  final int revision;
  final int? waveId;
  final double? price;
  final DateTime time;
  final String? failureCode;
  final bool applied;

  const ProductPriceChange({
    required this.id,
    required this.revision,
    this.waveId,
    required this.price,
    required this.time,
    this.failureCode,
    this.applied = false,
  });

  factory ProductPriceChange.fromJson(Map<String, dynamic> json) =>
      ProductPriceChange(
        id: json['id'],
        revision: json['revision'],
        waveId: json['wave_id'],
        price: double.tryParse(json['new_value'].toString()),
        time: DateTime.parse(json['change_time']).toUtc(),
        failureCode: json['failure_code'],
        applied: json['applied'] == true,
      );

  static List<ProductPriceChange> pending(
    Iterable<ProductPriceChange> changes,
  ) => changes.where((c) => !c.applied).toList()
    ..sort((a, b) {
      final order = a.time.compareTo(b.time);
      return order != 0 ? order : a.id.compareTo(b.id);
    });

  /// All instants that actually map to this wall time. No DST normalization.
  static List<DateTime> instants(DateTime wall, tz.Location location) =>
      OccasionTimeContext(location).instantsForWallTime(wall);
}
