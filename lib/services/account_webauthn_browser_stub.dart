bool get supportsWebAuthn => false;

Future<Map<String, Object?>> takeWebAuthnAssertion(
  Map<String, Object?> options,
) => throw UnsupportedError('WebAuthn requires a supported browser.');

bool get supportsWebAuthnCreation => false;

Future<Map<String, Object?>> createWebAuthnCredential(
  Map<String, Object?> options,
) => throw UnsupportedError('WebAuthn requires a supported browser.');
