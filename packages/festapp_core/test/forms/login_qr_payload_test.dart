import 'package:test/test.dart';
import 'package:festapp_core/forms.dart';

void main() {
  group('login_qr_payload', () {
    test('accepts only the typed reception login payload', () {
      final token = List.filled(43, 'A').join();
      final valid = 'festapp-login:v1:42:$token';
      expect(LoginQrPayload.tryParse(valid)?.occasion, 42);
      expect(LoginQrPayload.tryParse(valid)?.raw, valid);
      expect(
        LoginQrPayload.tryParse('550e8400-e29b-41d4-a716-446655440000'),
        isNull,
      );
      expect(LoginQrPayload.tryParse('ticket:v1:ABC'), isNull);
      expect(LoginQrPayload.tryParse('festapp-login:v2:42:$token'), isNull);
      expect(LoginQrPayload.tryParse('festapp-login:v1:42:short'), isNull);
      expect(LoginQrPayload.tryParse('  $valid\n')?.raw, valid);
    });
  });
}
