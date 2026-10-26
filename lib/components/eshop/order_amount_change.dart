/// Authoritative order amounts from the shared SQL projection. No client maths.
class OrderAmountChange {
  const OrderAmountChange(
      {required this.orderId,
      required this.beforeAmount,
      required this.afterAmount,
      required this.delta,
      required this.currencyCode,
      required this.beforeState,
      required this.afterState});
  final int orderId;
  final String beforeAmount,
      afterAmount,
      delta,
      currencyCode,
      beforeState,
      afterState;

  factory OrderAmountChange.fromJson(Map<String, dynamic> json) {
    final before = json['beforeAmount'] as String;
    final after = json['afterAmount'] as String;
    final delta = json['delta'] as String;
    final currency = json['currencyCode'] as String;
    if ([before, after, delta].any(
            (v) => v.length > 40 || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v)) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid authoritative order amount');
    }
    return OrderAmountChange(
        orderId: json['orderId'] as int,
        beforeAmount: before,
        afterAmount: after,
        delta: delta,
        currencyCode: currency,
        beforeState: json['beforeState'] as String,
        afterState: json['afterState'] as String);
  }
}
