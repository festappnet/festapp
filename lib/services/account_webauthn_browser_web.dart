import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

JSObject? get _publicKeyCredential =>
    globalContext.getProperty<JSObject?>('PublicKeyCredential'.toJS);

bool get supportsWebAuthn =>
    web.window.isSecureContext &&
    !_publicKeyCredential.isUndefinedOrNull &&
    web.window.navigator.has('credentials');

bool get supportsWebAuthnCreation =>
    supportsWebAuthn && web.window.navigator.credentials.has('create');

String _encode(JSArrayBuffer bytes) =>
    base64Url.encode(bytes.toDart.asUint8List()).replaceAll('=', '');

JSUint8Array _decode(String text) =>
    base64Url.decode(base64Url.normalize(text)).toJS;

Map<String, Object?> _binaryOptions(
  Map<String, Object?> options,
  String credentialList,
) {
  final credentials = options[credentialList];
  return {
    ...options,
    'challenge': _decode(options['challenge'] as String),
    if (credentials is List)
      credentialList: [
        for (final descriptor in credentials.cast<Map<String, Object?>>())
          {...descriptor, 'id': _decode(descriptor['id'] as String)},
      ],
  };
}

web.PublicKeyCredentialRequestOptions _requestOptions(
  JSObject constructor,
  Map<String, Object?> options,
) {
  final request = {...options, 'userVerification': 'required'};
  if (constructor.has('parseRequestOptionsFromJSON')) {
    return constructor.callMethod<web.PublicKeyCredentialRequestOptions>(
      'parseRequestOptionsFromJSON'.toJS,
      request.jsify(),
    );
  }
  return _binaryOptions(request, 'allowCredentials').jsify()
      as web.PublicKeyCredentialRequestOptions;
}

web.PublicKeyCredentialCreationOptions _creationOptions(
  JSObject constructor,
  Map<String, Object?> options,
) {
  final selection = options['authenticatorSelection'] as Map?;
  final creation = {
    ...options,
    'authenticatorSelection': {...?selection, 'userVerification': 'required'},
  };
  if (constructor.has('parseCreationOptionsFromJSON')) {
    return constructor.callMethod<web.PublicKeyCredentialCreationOptions>(
      'parseCreationOptionsFromJSON'.toJS,
      creation.jsify(),
    );
  }
  final user = creation['user'] as Map;
  return {
        ..._binaryOptions(creation, 'excludeCredentials'),
        'user': {...user, 'id': _decode(user['id'] as String)},
      }.jsify()
      as web.PublicKeyCredentialCreationOptions;
}

Map<String, Object?>? _credentialJson(web.PublicKeyCredential credential) {
  if (!credential.has('toJSON')) return null;
  final serialized = credential.callMethod<JSObject>('toJSON'.toJS).dartify();
  return Map<String, Object?>.from(serialized as Map);
}

Map<String, Object?> _credentialFields(web.PublicKeyCredential credential) => {
  'id': credential.id,
  'rawId': _encode(credential.rawId),
  'type': credential.type,
  'authenticatorAttachment': credential.authenticatorAttachment,
  'clientExtensionResults': credential.getClientExtensionResults().dartify(),
};

Future<Map<String, Object?>> takeWebAuthnAssertion(
  Map<String, Object?> options,
) async {
  final constructor = _publicKeyCredential;
  if (!supportsWebAuthn || constructor == null) {
    throw UnsupportedError('WebAuthn requires a supported browser.');
  }
  final response = await web.window.navigator.credentials
      .get(
        web.CredentialRequestOptions(
          publicKey: _requestOptions(constructor, options),
        ),
      )
      .toDart;
  if (response == null) throw StateError('WebAuthn assertion was cancelled.');
  final credential = response as web.PublicKeyCredential;
  final serialized = _credentialJson(credential);
  if (serialized != null) return serialized;
  final assertion = credential.response as web.AuthenticatorAssertionResponse;
  final userHandle = assertion.userHandle;
  return {
    ..._credentialFields(credential),
    'response': {
      'authenticatorData': _encode(assertion.authenticatorData),
      'clientDataJSON': _encode(assertion.clientDataJSON),
      'signature': _encode(assertion.signature),
      'userHandle': userHandle == null ? null : _encode(userHandle),
    },
  };
}

Future<Map<String, Object?>> createWebAuthnCredential(
  Map<String, Object?> options,
) async {
  final constructor = _publicKeyCredential;
  if (!supportsWebAuthnCreation || constructor == null) {
    throw UnsupportedError('WebAuthn requires a supported browser.');
  }
  final response = await web.window.navigator.credentials
      .create(
        web.CredentialCreationOptions(
          publicKey: _creationOptions(constructor, options),
        ),
      )
      .toDart;
  if (response == null) throw StateError('WebAuthn enrollment was cancelled.');
  final credential = response as web.PublicKeyCredential;
  final serialized = _credentialJson(credential);
  if (serialized != null) return serialized;
  final attestation =
      credential.response as web.AuthenticatorAttestationResponse;
  return {
    ..._credentialFields(credential),
    'response': {
      'attestationObject': _encode(attestation.attestationObject),
      'clientDataJSON': _encode(attestation.clientDataJSON),
      'transports': attestation.has('getTransports')
          ? attestation
                .getTransports()
                .toDart
                .map((value) => value.toDart)
                .toList()
          : [],
    },
  };
}
