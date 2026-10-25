import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'js/js_interop.dart';

extension ColorString on Color {
  String toHexString({bool includeAlpha = false}) {
    int red = (r * 255).round();
    int green = (g * 255).round();
    int blue = (b * 255).round();
    int alpha = (a * 255).round();

    final redHex = red.toRadixString(16).padLeft(2, '0');
    final greenHex = green.toRadixString(16).padLeft(2, '0');
    final blueHex = blue.toRadixString(16).padLeft(2, '0');
    final alphaHex = alpha.toRadixString(16).padLeft(2, '0');

    return '#${includeAlpha ? alphaHex + redHex + greenHex + blueHex : redHex + greenHex + blueHex}'
        .toUpperCase();
  }
}

class WebStylesHelper {
  static final JSInterop jsInterop = JSInterop();
  static void setMetaThemeColor(Color color) {
    if (kIsWeb) {
      jsInterop.callMethod("setMetaThemeColor", [color.toHexString()]);
    }
  }

  static void setBodyBackgroundColor(Color color) {
    if (kIsWeb) {
      jsInterop.callMethod("setBodyBackgroundColor", [color.toHexString()]);
    }
  }
}
