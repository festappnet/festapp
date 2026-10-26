import 'dart:convert';
import 'package:web/web.dart' as web;

Map<String, String>? consumeAuthHandoff() {
  final value = web.window.sessionStorage.getItem('_auth_handoff');
  if (value == null) return null;
  web.window.sessionStorage.removeItem('_auth_handoff');
  final map = jsonDecode(value) as Map<String, dynamic>;
  return map.map((k, v) => MapEntry(k, v.toString()));
}
