import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/backend_activation_service.dart';

void main() {
  const tenant = 'festival-test';
  const legacyUrl = 'https://legacy.supabase.co';
  const canonicalUrl = 'https://api.festapp.net';
  final canonicalBytes = utf8.encode(
    '{"schemaVersion":1,"tenantId":"$tenant","generation":1,'
    '"backend":"canonical"}\n',
  );
  final canonicalSha = sha256.convert(canonicalBytes).toString();
  String canonicalProfileSha(int organizationId) => sha256
      .convert(utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'tenantId': tenant,
        'generation': 1,
        'canonicalOrigin': canonicalUrl,
        'anonKeySha256':
            sha256.convert(utf8.encode('canonical-key')).toString(),
        'canonicalOrganizationId': organizationId,
      })))
      .toString();

  BackendActivationService service({
    required Map<String, String> storage,
    required Future<List<int>> Function(Uri) fetch,
    int legacyOrganizationId = 9,
    int canonicalOrganizationId = 12,
  }) =>
      BackendActivationService(
        tenantId: tenant,
        manifestUrl: 'https://app.example.test/backend-activation.json',
        canonicalManifestSha256: canonicalSha,
        legacySupabaseUrl: legacyUrl,
        legacyAnonKey: 'legacy-key',
        legacyOrganizationId: legacyOrganizationId,
        canonicalSupabaseUrl: canonicalUrl,
        canonicalAnonKey: 'canonical-key',
        canonicalOrganizationId: canonicalOrganizationId,
        canonicalProfileSha256: canonicalProfileSha(canonicalOrganizationId),
        read: (key) async => storage[key],
        write: (key, value) async => storage[key] = value,
        fetch: fetch,
      );

  test('explicit loopback debug override never reads production activation',
      () async {
    const override = String.fromEnvironment('FESTAPP_SUPABASE_URL');
    final host = Uri.tryParse(override)?.host;
    if (host != '127.0.0.1' && host != 'localhost') return;
    var touchedProduction = false;
    final resolved = await BackendActivationService(
      read: (_) async {
        touchedProduction = true;
        return 'canonical:1';
      },
      write: (_, __) async =>
          throw StateError('Must not write a production marker'),
      fetch: (_) async {
        touchedProduction = true;
        return canonicalBytes;
      },
    ).resolve();
    expect(touchedProduction, isFalse);
    expect(resolved.supabaseUrl, override);
    expect(resolved.isCanonical, isFalse);
  });

  test('defaults to the legacy writer when activation is unavailable',
      () async {
    final resolved = await service(
      storage: {},
      fetch: (_) async => throw Exception('offline'),
    ).resolve();

    expect(resolved.supabaseUrl, legacyUrl);
    expect(resolved.organizationId, 9);
    expect(resolved.installationGeneration('release-1'), 'release-1');
    expect(resolved.isCanonical, isFalse);
  });

  test('accepts only the exact canonical document and persists it', () async {
    final storage = <String, String>{};
    final first = await service(
      storage: storage,
      fetch: (_) async => canonicalBytes,
    ).resolve();
    expect(first.supabaseUrl, canonicalUrl);
    expect(first.organizationId, 12);
    expect(
      first.installationGeneration('release-1'),
      'release-1/backend-canonical-v1/organization-12',
    );
    expect(first.isCanonical, isTrue);

    final sticky = await service(
      storage: storage,
      fetch: (_) async => throw Exception('manifest regressed'),
    ).resolve();
    expect(sticky.supabaseUrl, canonicalUrl);
    expect(sticky.isCanonical, isTrue);
  });

  for (final mapping in const [
    ('csmostrava2026', 9, 12),
    ('cavfotofest', 3, 6),
    ('hvezdamorska', 4, 7),
  ]) {
    test(
        'switches the complete ${mapping.$1} profile ${mapping.$2} -> ${mapping.$3}',
        () async {
      final legacy = await service(
        storage: {},
        legacyOrganizationId: mapping.$2,
        canonicalOrganizationId: mapping.$3,
        fetch: (_) async => throw Exception('legacy phase'),
      ).resolve();
      expect(legacy.supabaseUrl, legacyUrl);
      expect(legacy.anonKey, 'legacy-key');
      expect(legacy.organizationId, mapping.$2);
      expect(legacy.installationGeneration('transition-v1'), 'transition-v1');

      final canonical = await service(
        storage: {},
        legacyOrganizationId: mapping.$2,
        canonicalOrganizationId: mapping.$3,
        fetch: (_) async => canonicalBytes,
      ).resolve();
      expect(canonical.supabaseUrl, canonicalUrl);
      expect(canonical.anonKey, 'canonical-key');
      expect(canonical.organizationId, mapping.$3);
      expect(
        canonical.installationGeneration('transition-v1'),
        'transition-v1/backend-canonical-v1/organization-${mapping.$3}',
      );
    });
  }

  test('rejects a modified or legacy activation response', () async {
    final storage = <String, String>{};
    final modified = utf8.encode(
      '{"schemaVersion":1,"tenantId":"$tenant","generation":0,'
      '"backend":"legacy"}\n',
    );
    final resolved = await service(
      storage: storage,
      fetch: (_) async => modified,
    ).resolve();

    expect(resolved.supabaseUrl, legacyUrl);
    expect(storage, isEmpty);
  });

  test('storage read and write failures keep the legacy writer', () async {
    final readFailure = BackendActivationService(
      tenantId: tenant,
      manifestUrl: 'https://app.example.test/backend-activation.json',
      canonicalManifestSha256: canonicalSha,
      legacySupabaseUrl: legacyUrl,
      legacyAnonKey: 'legacy-key',
      legacyOrganizationId: 9,
      canonicalSupabaseUrl: canonicalUrl,
      canonicalAnonKey: 'canonical-key',
      canonicalOrganizationId: 12,
      canonicalProfileSha256: canonicalProfileSha(12),
      read: (_) async => throw Exception('storage unavailable'),
      write: (_, __) async {},
      fetch: (_) async => canonicalBytes,
    );
    expect((await readFailure.resolve()).isCanonical, isFalse);

    final writeFailure = BackendActivationService(
      tenantId: tenant,
      manifestUrl: 'https://app.example.test/backend-activation.json',
      canonicalManifestSha256: canonicalSha,
      legacySupabaseUrl: legacyUrl,
      legacyAnonKey: 'legacy-key',
      legacyOrganizationId: 9,
      canonicalSupabaseUrl: canonicalUrl,
      canonicalAnonKey: 'canonical-key',
      canonicalOrganizationId: 12,
      canonicalProfileSha256: canonicalProfileSha(12),
      read: (_) async => null,
      write: (_, __) async => throw Exception('storage unavailable'),
      fetch: (_) async => canonicalBytes,
    );
    expect((await writeFailure.resolve()).isCanonical, isFalse);
  });
}
