import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';

void main() {
  test('widget images preserve the physical-to-logical pixel ratio', () {
    expect(
      StyleController.widgetImagePixelRatio(
        logicalSize: const Size(10, 8),
        imageSize: const Size(30, 24),
      ),
      3,
    );
  });
}
