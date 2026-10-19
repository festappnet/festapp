import 'package:festapp_core/eshop.dart';
import 'package:test/test.dart';

void main() {
  for (final code in [
    '2010',
    '3030',
    '0300',
    '0600',
    '2250',
    '5500',
    '2700',
    '0800',
  ]) {
    test(
      'email connection supports bank $code independently of legacy type',
      () {
        for (final number in ['123456/$code', 'CZ12${code}0000000000000000']) {
          expect(
            BankAccountModel(
              id: 1,
              accountNumber: number,
              type: 'OTHER',
            ).supportsEmailConnection,
            isTrue,
          );
        }
      },
    );
  }
  test('unsupported banks and malformed identifiers stay unavailable', () {
    for (final number in [null, '', 'CZ123030', '123456/0100', '123456/6210']) {
      expect(
        BankAccountModel(id: 1, accountNumber: number).supportsEmailConnection,
        isFalse,
      );
    }
  });
}
