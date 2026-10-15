class ClientCommandResponse {
  const ClientCommandResponse({
    required this.status,
    required this.code,
    required this.data,
    required this.replacements,
    required this.mutation,
  });

  final Map<String, dynamic> mutation;
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
    final mutation = response['mutation'];
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
    );
    if (mutation is! Map ||
        mutation['commandId'] is! String ||
        !uuid.hasMatch(mutation['commandId']) ||
        mutation['receiptId'] != mutation['commandId'] ||
        (mutation['commitId'] != null &&
            (mutation['commitId'] is! String ||
                !uuid.hasMatch(mutation['commitId']))) ||
        mutation['replayed'] is! bool ||
        mutation['occurredAt'] is! String ||
        DateTime.tryParse(mutation['occurredAt']) == null) {
      throw const FormatException('Invalid mutation identity');
    }
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
      mutation: mutation.cast<String, dynamic>(),
      status: status,
      code: code.toInt(),
      data: data.cast<String, dynamic>(),
      replacements: (sync['replacements'] as List)
          .map((item) => (item as Map).cast<String, dynamic>())
          .toList(growable: false),
    );
  }
}
