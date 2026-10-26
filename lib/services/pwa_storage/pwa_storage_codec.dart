import 'pwa_storage_port.dart';

Map<String, dynamic> pwaStringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

PwaStorageEstimate decodePwaStorageEstimate(Object? raw) {
  final value = pwaStringMap(raw);
  final details = <String, int>{};
  for (final entry in pwaStringMap(value['usageDetails']).entries) {
    if (entry.value case final num amount) details[entry.key] = amount.toInt();
  }
  return PwaStorageEstimate(
    usageBytes: (value['usage'] as num?)?.toInt(),
    quotaBytes: (value['quota'] as num?)?.toInt(),
    usageDetails: details,
  );
}

PwaShellReport decodePwaShellReport(Object? raw) {
  final value = pwaStringMap(raw);
  return PwaShellReport(
    current: value['current'] as String?,
    live: _strings(value['live']),
    unknownClients: (value['unknown'] as num?)?.toInt() ?? 0,
    retained: _strings(value['retained']),
    deletable: _strings(value['deletable']),
    deleted: _strings(value['deleted']),
    blocker: value['blocker'] as String?,
  );
}

PwaStorageReport decodePwaStorageReport(Object? raw) {
  final value = pwaStringMap(raw);
  return PwaStorageReport(
    estimate: decodePwaStorageEstimate(value['estimate']),
    shells: decodePwaShellReport(value['shells']),
  );
}
