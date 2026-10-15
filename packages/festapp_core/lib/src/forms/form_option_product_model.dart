import 'package:festapp_core/forms.dart';
import 'package:festapp_core/json_values.dart';

class FormOptionProductModel extends FormOptionDefinition {
  static const String metaMaximum = "maximum";
  static const String metaOrderedCount = "ordered_count";
  static const String metaCurrencyCode = "currency_code";
  static const String metaIsDynamicallyAvailable =
      "is_available_dynamic_capacity";

  final double price;
  final int? maximum;
  final int? orderedCount;
  final String? currencyCode;
  final bool? isDynamicallyAvailable;
  final Map<String, dynamic>? data;

  FormOptionProductModel(
    super.id,
    super.title, {
    this.price = 0.0,
    this.maximum,
    this.orderedCount,
    this.currencyCode,
    this.isDynamicallyAvailable,
    Map<String, dynamic>? data,
    super.type,
    super.description,
  }) : data = data == null
           ? null
           : freezeJsonValue(data) as Map<String, dynamic>;

  /// Returns true if the product has capacity and is dynamically available.
  /// It checks static limits (`maximum` vs `orderedCount`) and the dynamic availability flag from the backend.
  /// If `isDynamicallyAvailable` is null, it's treated as true to ensure backward compatibility.
  bool get isAvailable =>
      ((maximum == null || maximum == 0) ||
          ((orderedCount ?? 0) < (maximum ?? 0))) &&
      (isDynamicallyAvailable ?? true);

  /// Returns the deposit amount from product.data.deposit.amount, or null if not set.
  double? get depositAmount {
    if (data == null) return null;
    final deposit = data!['deposit'];
    if (deposit is! Map) return null;
    final val = deposit['amount'];
    if (val is num && val > 0) return val.toDouble();
    if (val is String) {
      final parsed = double.tryParse(val);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  /// Returns the visual-only meta surcharge amount from data.meta_surcharge.amount,
  /// or null if not set / is zero. Negative values represent discounts (slevy).
  /// Has NO impact on order totals.
  double? get metaSurchargeAmount {
    if (data == null) return null;
    final ms = data!['meta_surcharge'];
    if (ms is! Map) return null;
    final val = ms['amount'];
    if (val is num && val != 0) return val.toDouble();
    if (val is String) {
      final parsed = double.tryParse(val);
      if (parsed != null && parsed != 0) return parsed;
    }
    return null;
  }

  /// Returns the meta surcharge currency code (independent of product.currencyCode),
  /// or null if not set.
  String? get metaSurchargeCurrency {
    if (data == null) return null;
    final ms = data!['meta_surcharge'];
    if (ms is! Map) return null;
    final val = ms['currency'];
    return (val is String && val.isNotEmpty) ? val : null;
  }
}
