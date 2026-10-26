import 'package:supabase_flutter/supabase_flutter.dart';

typedef AppConfigRpcInvoker = Future<dynamic> Function(String functionName);

/// Selects the transition app-config contract when the backend supports it,
/// while keeping clients usable against legacy projects during the rollout.
/// Only PostgREST's exact missing-function response is eligible for fallback;
/// authorization, connectivity, and server failures remain visible.
Future<dynamic> loadAppConfigWithLegacyFallback({
  required AppConfigRpcInvoker invoke,
  bool useLegacyContract = false,
}) async {
  if (useLegacyContract) return _loadLegacyAppConfig(invoke);

  try {
    return await invoke('get_app_config_v219');
  } catch (error) {
    if (!_isMissingFunction(error, 'get_app_config_v219')) rethrow;
    return _loadLegacyAppConfig(invoke);
  }
}

Future<Map<String, dynamic>> _loadLegacyAppConfig(
  AppConfigRpcInvoker invoke,
) async {
  dynamic legacy;
  try {
    legacy = await invoke('get_app_config_v218');
  } catch (error) {
    if (!_isMissingFunction(error, 'get_app_config_v218')) rethrow;
    legacy = await invoke('get_app_config_v2');
  }
  if (legacy is! Map) {
    throw StateError('Legacy app-config response is not an object');
  }
  return <String, dynamic>{
    ...legacy.cast<String, dynamic>(),
    'client_sync_v1': false,
  };
}

bool _isMissingFunction(Object error, String functionName) {
  if (error is PostgrestException && error.code == 'PGRST202') return true;
  final description = error.toString();
  return description.contains('PGRST202') && description.contains(functionName);
}
