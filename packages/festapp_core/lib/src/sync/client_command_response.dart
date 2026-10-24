/// Standard mutation envelope. Domain adapters own acceptance policy.
class ClientCommandResponse {
  const ClientCommandResponse({
    required this.status,
    required this.code,
    required this.data,
    required this.replacements,
  });

  final String status;
  final int code;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> replacements;

  factory ClientCommandResponse.from(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid client command response');
    }
    final response = raw.cast<String, dynamic>();
    final status = response['status'];
    final code = response['code'];
    final data = response['data'];
    final sync = response['sync'];
    if (status is! String ||
        !const {
          'applied',
          'unchanged',
          'rejected',
          'conflict',
        }.contains(status) ||
        code is! num ||
        data is! Map ||
        sync is! Map ||
        sync['replacements'] is! List) {
      throw const FormatException('Invalid client command envelope');
    }
    return ClientCommandResponse(
      status: status,
      code: code.toInt(),
      data: data.cast<String, dynamic>(),
      replacements: (sync['replacements'] as List)
          .map((item) => (item as Map).cast<String, dynamic>())
          .toList(growable: false),
    );
  }
}
