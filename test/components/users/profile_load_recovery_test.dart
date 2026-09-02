import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/profile_load_recovery.dart';

void main() {
  test('uses bootstrap identity when remote profile never completes', () async {
    final pending = Completer<String?>();

    final profile = await loadProfileWithFallback<String>(
      loadFresh: () => pending.future,
      loadCached: () async => null,
      loadBootstrap: () => 'bootstrap-profile',
      freshTimeout: const Duration(milliseconds: 10),
    );

    expect(profile, 'bootstrap-profile');
  });

  test('prefers cached identity after remote profile fails', () async {
    final profile = await loadProfileWithFallback<String>(
      loadFresh: () => Future<String?>.error(StateError('RPC failed')),
      loadCached: () async => 'cached-profile',
      loadBootstrap: () => 'bootstrap-profile',
    );

    expect(profile, 'cached-profile');
  });

  test('keeps a successfully enriched profile', () async {
    final profile = await loadProfileWithFallback<String>(
      loadFresh: () async => 'fresh-profile',
      loadCached: () async => 'cached-profile',
      loadBootstrap: () => 'bootstrap-profile',
    );

    expect(profile, 'fresh-profile');
  });
}
