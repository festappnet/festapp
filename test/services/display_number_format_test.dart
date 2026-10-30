import 'package:festapp_core/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared number policy covers thresholds, signs, decimals and locales',
    () {
      for (final entry in <num, String>{
        0: '0',
        1350: '1350',
        9999: '9999',
        10000: '10\u00a0000',
        -1350: '-1350',
        -10000: '-10\u00a0000',
        1350.5: '1350,5',
      }.entries) {
        expect(formatDisplayNumber(entry.key, locale: 'cs'), entry.value);
        expect(
          formatExactDisplayNumber(entry.key.toString(), locale: 'cs'),
          entry.value,
        );
      }
      expect(formatDisplayNumber(1350, locale: 'en'), '1350');
      expect(formatDisplayNumber(10000, locale: 'en'), '10,000');
      expect(
        formatDisplayNumber(1350.5, locale: 'de', decimalDigits: 2),
        '1350,50',
      );
    },
  );

  test(
    'currency keeps its spacing and precision in simple and full formats',
    () {
      for (final simple in [false, true]) {
        expect(
          formatDisplayCurrency(
            1350.5,
            locale: 'cs',
            name: 'CZK',
            symbol: 'Kč',
            simple: simple,
            decimalDigits: 2,
          ),
          '1350,50\u00a0Kč',
        );
        expect(
          formatDisplayCurrency(
            10000,
            locale: 'cs',
            name: 'CZK',
            symbol: 'Kč',
            simple: simple,
            decimalDigits: 0,
          ),
          '10\u00a0000\u00a0Kč',
        );
      }
    },
  );

  test(
    'exact numbers retain all cents, large integers and unparseable input',
    () {
      expect(formatExactDisplayNumber('9999.99', locale: 'cs'), '9999,99');
      expect(
        formatExactDisplayNumber('-10000.00', locale: 'cs'),
        '-10\u00a0000,00',
      );
      expect(
        formatExactDisplayNumber('12345678901234567890.12', locale: 'cs'),
        '12\u00a0345\u00a0678\u00a0901\u00a0234\u00a0567\u00a0890,12',
      );
      expect(formatExactDisplayNumber('unknown', locale: 'cs'), 'unknown');
    },
  );
}
