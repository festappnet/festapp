import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/reception/login_qr_barcode.dart';
import 'package:fstapp/components/reception/login_qr_payload.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test('accepts only the typed reception login payload', () {
    final token = List.filled(43, 'A').join();
    final valid = 'festapp-login:v1:42:$token';
    expect(LoginQrPayload.tryParse(valid)?.occasion, 42);
    expect(LoginQrPayload.tryParse(valid)?.raw, valid);
    expect(LoginQrPayload.tryParse('550e8400-e29b-41d4-a716-446655440000'),
        isNull);
    expect(LoginQrPayload.tryParse('ticket:v1:ABC'), isNull);
    expect(LoginQrPayload.tryParse('festapp-login:v2:42:$token'), isNull);
    expect(LoginQrPayload.tryParse('festapp-login:v1:42:short'), isNull);
    expect(LoginQrPayload.tryParse('  $valid\n')?.raw, valid);
  });

  test('selects a valid login QR from a multi-barcode camera capture', () {
    final valid = 'festapp-login:v1:643:${List.filled(43, 'A').join()}';
    final parsed = LoginQrPayload.firstValid([
      null,
      'https://festapp.net',
      valid,
    ]);
    expect(parsed?.occasion, 643);
    expect(parsed?.raw, valid);
  });

  test('accepts the scanner display value when rawValue is unavailable', () {
    final valid = 'festapp-login:v1:643:${List.filled(43, 'A').join()}';

    final parsed = loginQrFromBarcodes([
      Barcode(rawValue: null, displayValue: valid),
    ]);

    expect(parsed?.raw, valid);
  });

  test('accepts decoded scanner bytes when text values are unavailable', () {
    final valid = 'festapp-login:v1:643:${List.filled(43, 'A').join()}';

    final parsed = loginQrFromBarcodes([
      Barcode(
        rawDecodedBytes: DecodedBarcodeBytes(
          bytes: Uint8List.fromList(utf8.encode(valid)),
        ),
      ),
    ]);

    expect(parsed?.raw, valid);
  });
}
