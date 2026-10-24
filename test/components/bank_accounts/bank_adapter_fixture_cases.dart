import 'synchronization_control_cases.dart' as controls;
import 'token_error_view_cases.dart' as errors;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'token_update_cases.dart' as tokens;
import '../../support/fixtures/client_fixture_cases.dart' as lifecycle;

void main() {
  final suites = [
    () => group('bank_tokens', tokens.main),
    () => group('bank_lifecycle', lifecycle.main),
    () => group('synchronization_control', controls.main),
    () => group('token_error_view', errors.main)
  ];
  final ordered = Platform.environment['FESTAPP_FIXTURE_ORDER'] == 'reverse'
      ? suites.reversed
      : suites;
  for (final register in ordered) {
    register();
  }
}
