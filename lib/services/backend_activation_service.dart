import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:http/http.dart' as http;

typedef BackendActivationRead = Future<String?> Function(String key);
typedef BackendActivationWrite = Future<void> Function(
    String key, String value);
typedef BackendActivationFetch = Future<List<int>> Function(Uri uri);

class ResolvedBackend {
  const ResolvedBackend({
    required this.supabaseUrl,
    required this.anonKey,
    required this.organizationId,
    required this.profileSha256,
    required this.isCanonical,
  });

  final String supabaseUrl;
  final String anonKey;
  final int organizationId;
  final String profileSha256;
  final bool isCanonical;

  String installationGeneration(String baseGeneration) => isCanonical
      ? '$baseGeneration/backend-canonical-v1/organization-$organizationId'
      : baseGeneration;
}

/// Resolves the one backend a process may use before Supabase is initialized.
///
/// Transition releases default to their compiled legacy backend. The only
/// remotely accepted instruction is the exact, build-approved canonical
/// activation document identified by its SHA-256. Once accepted, the local
/// marker is monotonic: an unavailable or older deployment can never route the
/// installation back to the legacy writer.
class BackendActivationService {
  BackendActivationService({
    String? tenantId,
    String? manifestUrl,
    String? canonicalManifestSha256,
    String? legacySupabaseUrl,
    String? legacyAnonKey,
    String? canonicalSupabaseUrl,
    String? canonicalAnonKey,
    int? legacyOrganizationId,
    int? canonicalOrganizationId,
    String? canonicalProfileSha256,
    BackendActivationRead? read,
    BackendActivationWrite? write,
    BackendActivationFetch? fetch,
  })  : tenantId = tenantId ?? AppConfig.backendActivationTenantId,
        manifestUrl = manifestUrl ?? AppConfig.backendActivationManifestUrl,
        canonicalManifestSha256 = canonicalManifestSha256 ??
            AppConfig.backendActivationCanonicalManifestSha256,
        legacySupabaseUrl = legacySupabaseUrl ?? AppConfig.effectiveSupabaseUrl,
        legacyAnonKey = legacyAnonKey ?? AppConfig.effectiveSupabaseAnonKey,
        canonicalSupabaseUrl = canonicalSupabaseUrl ??
            AppConfig.backendActivationCanonicalSupabaseUrl,
        canonicalAnonKey =
            canonicalAnonKey ?? AppConfig.backendActivationCanonicalAnonKey,
        legacyOrganizationId = legacyOrganizationId ?? AppConfig.organization,
        canonicalOrganizationId = canonicalOrganizationId ??
            AppConfig.backendActivationCanonicalOrganizationId,
        canonicalProfileSha256 = canonicalProfileSha256 ??
            AppConfig.backendActivationCanonicalProfileSha256,
        _read = read ?? ((key) => StorageHelper.get(key)),
        _write = write ?? ((key, value) => StorageHelper.set(key, value)),
        _fetch = fetch ?? _fetchManifest;

  static const int schemaVersion = 1;
  static const int canonicalGeneration = 1;
  static const String _markerPrefix = 'backend_activation_v1/';
  static const String _canonicalMarker = 'canonical:1';

  final String tenantId;
  final String manifestUrl;
  final String canonicalManifestSha256;
  final String legacySupabaseUrl;
  final String legacyAnonKey;
  final String canonicalSupabaseUrl;
  final String canonicalAnonKey;
  final int legacyOrganizationId;
  final int canonicalOrganizationId;
  final String canonicalProfileSha256;
  final BackendActivationRead _read;
  final BackendActivationWrite _write;
  final BackendActivationFetch _fetch;

  bool get isEnabled =>
      tenantId.isNotEmpty &&
      manifestUrl.isNotEmpty &&
      canonicalManifestSha256.isNotEmpty &&
      canonicalSupabaseUrl.isNotEmpty &&
      canonicalAnonKey.isNotEmpty &&
      canonicalOrganizationId > 0 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(canonicalProfileSha256);

  Future<ResolvedBackend> resolve() async {
    // An explicitly configured loopback debug backend must remain local even
    // if a production activation document or cached marker is available.
    const localOverride = String.fromEnvironment('FESTAPP_SUPABASE_URL');
    final overrideHost = Uri.tryParse(localOverride)?.host;
    if (kDebugMode &&
        localOverride == legacySupabaseUrl &&
        (overrideHost == '127.0.0.1' || overrideHost == 'localhost')) {
      return _legacy;
    }
    if (!isEnabled) return _legacy;

    final markerKey = '$_markerPrefix$tenantId';
    try {
      if (await _read(markerKey) == _canonicalMarker) return _canonical;
    } catch (_) {
      return _legacy;
    }

    try {
      final bytes = await _fetch(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 2));
      if (sha256.convert(bytes).toString() != canonicalManifestSha256) {
        return _legacy;
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic> ||
          value.length != 4 ||
          value['schemaVersion'] != schemaVersion ||
          value['tenantId'] != tenantId ||
          value['generation'] != canonicalGeneration ||
          value['backend'] != 'canonical') {
        return _legacy;
      }
      await _write(markerKey, _canonicalMarker);
      return _canonical;
    } catch (_) {
      return _legacy;
    }
  }

  ResolvedBackend get _legacy => ResolvedBackend(
        supabaseUrl: legacySupabaseUrl,
        anonKey: legacyAnonKey,
        organizationId: legacyOrganizationId,
        profileSha256: '',
        isCanonical: false,
      );

  ResolvedBackend get _canonical => ResolvedBackend(
        supabaseUrl: canonicalSupabaseUrl,
        anonKey: canonicalAnonKey,
        organizationId: canonicalOrganizationId,
        profileSha256: canonicalProfileSha256,
        isCanonical: true,
      );

  static Future<List<int>> _fetchManifest(Uri uri) async {
    final response = await http.get(uri, headers: const {
      'cache-control': 'no-cache',
    });
    if (response.statusCode != 200) {
      throw StateError(
          'Backend activation manifest returned ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
