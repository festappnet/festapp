import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/report_number_format.dart';

void main() {
  test('money retains exact cents beyond double precision', () {
    expect(formatReportNumber('12345678901234567890.12', locale: 'cs'),
        '12\u00a0345\u00a0678\u00a0901\u00a0234\u00a0567\u00a0890,12');
    expect(formatReportNumber('-1046778.22', locale: 'cs'),
        '-1\u00a0046\u00a0778,22');
  });
  test('formatting follows locale and preserves zero and fractional digits',
      () {
    expect(formatReportNumber('1046778.22', locale: 'en'), '1,046,778.22');
    expect(formatReportNumber('1046778.22', locale: 'de'), '1.046.778,22');
    expect(formatReportNumber('0.00', locale: 'cs'), '0,00');
    expect(formatReportNumber('1000', locale: 'cs'), '1\u00a0000');
  });
}
