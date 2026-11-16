/// Typed boundary for the server-owned payment policy. Invalid JSON fails closed.
enum PaymentPolicyMode { inherit, enabled, disabled }

enum PaymentPolicyOrigin { organization, unit }

class PaymentMethodPolicy {
  const PaymentMethodPolicy({
    required this.id,
    required this.mode,
    required this.origin,
    required this.organizationEnabled,
    required this.enabled,
    required this.configured,
    required this.ready,
    required this.canConfigure,
  });

  final String id;
  final PaymentPolicyMode mode;
  final PaymentPolicyOrigin origin;
  final bool organizationEnabled, enabled, configured, ready, canConfigure;

  factory PaymentMethodPolicy.fromJson(String id, Object? value) {
    final json = _object(value);
    if (json['id'] != id) {
      throw const FormatException('Payment method mismatch');
    }
    return PaymentMethodPolicy(
      id: id,
      mode: _enum(PaymentPolicyMode.values, _string(json, 'mode')),
      origin: _enum(PaymentPolicyOrigin.values, _string(json, 'inheritedFrom')),
      organizationEnabled: _boolean(json, 'organizationEnabled'),
      enabled: _boolean(json, 'policyEnabled'),
      configured: _boolean(json, 'configured'),
      ready: _boolean(json, 'ready'),
      canConfigure: _boolean(json, 'canConfigure'),
    );
  }
}

class PaymentPolicy {
  PaymentPolicy({
    required this.organizationId,
    required this.unitId,
    required this.revision,
    required this.preferredMethod,
    required Map<String, PaymentMethodPolicy> methods,
  }) : methods = Map.unmodifiable(methods);

  final int organizationId, revision;
  final int? unitId;
  final String? preferredMethod;
  final Map<String, PaymentMethodPolicy> methods;

  factory PaymentPolicy.fromJson(Object? value) {
    final json = _object(value);
    final methods = _object(json['methods']);
    final preferred = json['preferredMethod'];
    if (preferred != null && preferred is! String) {
      throw const FormatException('Invalid preferred method');
    }
    return PaymentPolicy(
      organizationId: _integer(json, 'organizationId'),
      unitId: json['unitId'] == null ? null : _integer(json, 'unitId'),
      revision: _integer(json, 'revision'),
      preferredMethod: preferred as String?,
      methods: methods.map(
        (id, data) => MapEntry(id, PaymentMethodPolicy.fromJson(id, data)),
      ),
    );
  }
}

class PaymentPolicyChange {
  const PaymentPolicyChange({
    required this.organizationId,
    this.unitId,
    required this.method,
    required this.mode,
    this.preferred = false,
  });
  final int organizationId;
  final int? unitId;
  final String method;
  final PaymentPolicyMode mode;
  final bool preferred;

  Map<String, Object?> toJson() => {
    'organizationId': organizationId,
    if (unitId != null) 'unitId': unitId,
    'method': method,
    'mode': mode.name,
    if (preferred) 'preferredMethod': method,
  };
}

class PaymentPolicyImpact {
  const PaymentPolicyImpact({
    required this.openCollections,
    required this.pendingRequests,
    required this.issuedReferences,
    required this.pendingBankInstructions,
    required this.undispatchedIntents,
    required this.dispatchedIntents,
    required this.unknownIntents,
    required this.obligations,
  });
  final int openCollections,
      pendingRequests,
      issuedReferences,
      pendingBankInstructions;
  final int undispatchedIntents, dispatchedIntents, unknownIntents, obligations;

  factory PaymentPolicyImpact.fromJson(Object? value) {
    final json = _object(value);
    final intents = _object(json['providerIntents']);
    return PaymentPolicyImpact(
      openCollections: _integer(json, 'openCollections'),
      pendingRequests: _integer(json, 'pendingRequests'),
      issuedReferences: _integer(json, 'issuedReferences'),
      pendingBankInstructions: _integer(json, 'pendingBankInstructions'),
      obligations: _integer(json, 'obligations'),
      undispatchedIntents: _integer(intents, 'undispatched'),
      dispatchedIntents: _integer(intents, 'dispatched'),
      unknownIntents: _integer(intents, 'unknown'),
    );
  }
}

class PaymentPolicyPreview {
  const PaymentPolicyPreview({
    required this.change,
    required this.impact,
    required this.confirmation,
  });
  final PaymentPolicyChange change;
  final PaymentPolicyImpact impact;
  final String confirmation;

  factory PaymentPolicyPreview.fromJson(
    PaymentPolicyChange change,
    Object? value,
  ) {
    final json = _object(value);
    final confirmation = _string(json, 'confirmation');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(confirmation)) {
      throw const FormatException('Invalid policy confirmation');
    }
    return PaymentPolicyPreview(
      change: change,
      impact: PaymentPolicyImpact.fromJson(json['impact']),
      confirmation: confirmation,
    );
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected payment policy object');
  }
  return Map<String, Object?>.from(value);
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid policy field: $key');
  return value;
}

bool _boolean(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid policy field: $key');
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('Invalid policy field: $key');
  }
  return value;
}

T _enum<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown policy value: $name');
}
