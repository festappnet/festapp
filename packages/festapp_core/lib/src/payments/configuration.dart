/// Builtin method identities shared by all Dart adapters. SQL owns availability.
bool isBuiltinPaymentMethod(String? method) => method == 'bank' || method == 'cash';

/// Canonical saved payment choice. Legacy Stripe aliases are decoded here only.
class FormPaymentConfiguration {
  const FormPaymentConfiguration({this.bankEnabled = false, this.cashEnabled = false, this.cashInstructions = '', this.connections = const {}});
  final bool bankEnabled;
  final bool cashEnabled;
  final String cashInstructions;
  final Map<String, String> connections;
  factory FormPaymentConfiguration.fromJson(Map? value) {
    final raw = value?['providerConnections'];
    if (raw != null && raw is! Map) throw const FormatException('Invalid provider connections');
    final connections = <String, String>{};
    for (final entry in (raw as Map? ?? {}).entries) {
      if (entry.key is! String || entry.value is! String) throw const FormatException('Invalid provider connection');
      connections[entry.key as String] = entry.value as String;
    }
    final legacy = value?['stripeConnectionId'];
    if (legacy != null) {
      if (legacy is! String || (connections['stripe'] != null && connections['stripe'] != legacy)) {
        throw const FormatException('Conflicting Stripe recipient');
      }
      connections['stripe'] = legacy;
    }
    return FormPaymentConfiguration(bankEnabled: value?['bankEnabled'] == true, cashEnabled: value?['cashEnabled'] == true, cashInstructions: value?['cashInstructions'] as String? ?? '', connections: Map.unmodifiable(connections));
  }
  Map<String, dynamic> toJson() => {'bankEnabled': bankEnabled, 'cashEnabled': cashEnabled, 'cashInstructions': cashInstructions, 'providerConnections': Map<String, String>.from(connections)};
  static void normalizeDraft(Map<String, dynamic> data) {
    final form = data['formDraft'];
    final meta = form is Map ? form['data'] : null;
    final saved = data['payments'] ?? (meta is Map ? meta['payments'] : null);
    final config = FormPaymentConfiguration.fromJson(saved is Map ? saved : null);
    final legacy = data.remove('paymentMethod');
    var bank = config.bankEnabled;
    var connections = config.connections;
    if (legacy == 'bank') { bank = true; connections = {}; }
    else if (legacy is String) {
      bank = legacy == 'both';
      connections = legacy == 'both' ? connections : {if (connections[legacy] != null) legacy: connections[legacy]!};
      if (connections.isEmpty) data['paymentRepairRequired'] = true;
    }
    data['payments'] = FormPaymentConfiguration(bankEnabled: bank, cashEnabled: config.cashEnabled, cashInstructions: config.cashInstructions, connections: connections).toJson();
  }
}
