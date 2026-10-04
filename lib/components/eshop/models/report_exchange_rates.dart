/// A dated indicative CNB snapshot. Display conversions use integer arithmetic.
class ReportExchangeRates {
  final DateTime date;
  final Map<String, ({BigInt numerator, BigInt denominator, String label})>
      rates;
  ReportExchangeRates._(this.date, this.rates);
  factory ReportExchangeRates.fromJson(Map<String, dynamic> json) {
    if (json['source'] != 'CNB' || json['base'] != 'CZK') {
      throw const FormatException('Invalid exchange rate source');
    }
    final date = DateTime.parse('${json['date']}T00:00:00Z');
    final rates =
        <String, ({BigInt numerator, BigInt denominator, String label})>{};
    for (final entry in (json['rates'] as Map<String, dynamic>).entries) {
      final amount = entry.value['amount'] as String;
      final rate = entry.value['rate'] as String;
      if (!RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(rate) ||
          !RegExp(r'^\d+$').hasMatch(amount)) {
        throw const FormatException('Invalid exchange rate');
      }
      final parts = rate.split('.');
      final numerator = BigInt.parse(parts.join());
      final denominator =
          BigInt.from(10).pow(parts.length == 1 ? 0 : parts[1].length) *
              BigInt.parse(amount);
      if (numerator <= BigInt.zero || denominator <= BigInt.zero) {
        throw const FormatException('Invalid exchange rate');
      }
      rates[entry.key] = (
        numerator: numerator,
        denominator: denominator,
        label: '$amount ${entry.key} = $rate CZK'
      );
    }
    return ReportExchangeRates._(date, rates);
  }
  BigInt toCzk(BigInt cents, String currency) {
    if (currency == 'CZK') return cents;
    final rate = rates[currency];
    if (rate == null) throw const FormatException('Missing exchange rate');
    final scaled = cents.abs() * rate.numerator;
    final rounded = (scaled * BigInt.two + rate.denominator) ~/
        (rate.denominator * BigInt.two);
    return cents.isNegative ? -rounded : rounded;
  }
}
