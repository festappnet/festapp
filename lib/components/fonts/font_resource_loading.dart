import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class FontResourceContextChanged extends StateError {
  FontResourceContextChanged() : super('Ticket context changed');
}

/// Retry safe font reads before exposing a temporary outage to the editor.
/// Denied access, invalid resources and programming errors remain failures.
Future<T> readFontResource<T>(Future<T> Function() read) async {
  const delays = [
    Duration(milliseconds: 150),
    Duration(milliseconds: 600),
    Duration(seconds: 5),
  ];
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } catch (error) {
      final transient =
          error is TimeoutException ||
          error is http.ClientException ||
          error is FlutterError &&
              error.toString().contains('Unable to load asset') ||
          error is FunctionException &&
              (error.status == 0 ||
                  error.status == 408 ||
                  error.status == 429 ||
                  error.status >= 500) ||
          error is FontResourceContextChanged;
      if (!transient || attempt == delays.length) rethrow;
      await Future<void>.delayed(delays[attempt]);
    }
  }
}
