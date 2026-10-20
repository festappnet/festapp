import 'dart:convert';

/// Keeps the authoritative machine reason and issue payload available to hosts.
class BlueprintCommandRejection implements Exception {
  BlueprintCommandRejection(this.code, Map<String, dynamic> payload)
      : data = Map.unmodifiable(
            jsonDecode(jsonEncode(payload)) as Map<String, dynamic>);
  final int code;
  final Map<String, dynamic> data;
  String get reason => data['reason']?.toString() ?? 'command_rejected';
  List<Map<String, dynamic>> get issues =>
      List.unmodifiable((data['issues'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.unmodifiable(e as Map)));
  @override
  String toString() => reason;
}
