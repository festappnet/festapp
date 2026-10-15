import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  group('reception_command_error', () {
    test('existing e-mail conflict is a user-correctable reception error', () {
      final error = ReceptionCommandException({
        'code': 409,
        'message': 'email_already_exists',
      });

      expect(error.kind, ReceptionCommandError.emailAlreadyExists);
    });

    test('unknown command failures stay classified as unexpected', () {
      final error = ReceptionCommandException({
        'code': 500,
        'message': 'future_server_failure',
      });

      expect(error.kind, ReceptionCommandError.unexpected);
    });
  });
}
