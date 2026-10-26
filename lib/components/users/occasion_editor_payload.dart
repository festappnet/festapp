/// Raw, dependency-free representation of the single
/// `get_occasion_users_for_edit` RPC response.
class OccasionEditorPayload {
  final bool isSuccess;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> forms;
  final Map<String, List<Map<String, dynamic>>> services;

  const OccasionEditorPayload({
    required this.isSuccess,
    required this.users,
    required this.forms,
    required this.services,
  });

  factory OccasionEditorPayload.fromRpc(dynamic result) {
    if (result is! Map || result['code'] != 200 || result['data'] is! Map) {
      return const OccasionEditorPayload(
        isSuccess: false,
        users: [],
        forms: [],
        services: {},
      );
    }

    final data = Map<String, dynamic>.from(result['data'] as Map);
    final rawServices = data['services'] is Map
        ? Map<String, dynamic>.from(data['services'] as Map)
        : <String, dynamic>{};

    List<Map<String, dynamic>> rows(dynamic value) => value is List
        ? value.map((row) => Map<String, dynamic>.from(row as Map)).toList()
        : <Map<String, dynamic>>[];

    return OccasionEditorPayload(
      isSuccess: true,
      users: rows(data['occasion_users']),
      forms: rows(data['forms']),
      services: {
        for (final entry in rawServices.entries) entry.key: rows(entry.value),
      },
    );
  }
}
