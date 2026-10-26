import 'dart:convert';
import 'dart:typed_data';

import 'package:festapp_core/forms.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

LoginQrPayload? loginQrFromBarcodes(Iterable<Barcode> barcodes) {
  for (final barcode in barcodes) {
    final parsed = LoginQrPayload.firstValid([
      barcode.rawValue,
      barcode.displayValue,
      _decodedText(barcode.rawDecodedBytes),
    ]);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _decodedText(BarcodeBytes? value) {
  final Uint8List? bytes = switch (value) {
    DecodedBarcodeBytes(:final bytes) => bytes,
    DecodedVisionBarcodeBytes(:final bytes) => bytes,
    null => null,
  };
  if (bytes == null) return null;
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
