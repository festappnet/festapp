import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  final cases = jsonDecode(File('../../shared/email/address-cases.json').readAsStringSync()) as List;
  for (final c in cases) {
    test(jsonEncode(c['email']), () {
      expect(EmailAddress.isValid(c['email'] as String), c['valid']);
    });
  }
}
