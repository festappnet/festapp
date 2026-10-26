import 'package:festapp_core/eshop.dart';
import 'package:test/test.dart';

void main() {
  test('customer label trims parts and prefers names over email', () {
    expect(
      formatCustomerLabel(name: ' Jana ', surname: ' Nováková ', email: 'mail'),
      'Jana Nováková',
    );
    expect(formatCustomerLabel(name: ' ', surname: ' Nováková '), 'Nováková');
    expect(formatCustomerLabel(name: ' Jana ', surname: ''), 'Jana');
    expect(
      formatCustomerLabel(
        name: ' ',
        surname: ' ',
        email: ' user@example.invalid ',
      ),
      'user@example.invalid',
    );
    expect(formatCustomerLabel(), '');
    expect(formatCustomerLabel(email: ' '), '');
  });
}
