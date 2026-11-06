import 'package:festapp_core/payments.dart';
import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';
void main() {
  const id = '12345678-1234-4234-8234-123456789abc';
  test('bank and provider identities survive canonical authoring roundtrip', () {
    final snapshot = FormMetadata.authoringSettingsSnapshot({'payments': {'bankEnabled': true, 'stripeConnectionId': id, 'providerConnections': {'other': id}}});
    expect(snapshot['payments'], {'bankEnabled': true, 'cashEnabled': false, 'cashInstructions': '', 'providerConnections': {'stripe': id, 'other': id}});
    expect(FormPaymentConfiguration.fromJson(snapshot['payments']).toJson(), snapshot['payments']);
  });
  test('legacy both keeps its exact saved provider and never selects another', () {
    final draft = <String,dynamic>{'paymentMethod': 'both','formDraft': {'data': {'payments': {'bankEnabled': true, 'cashEnabled': false, 'cashInstructions': '', 'providerConnections': {'other': id}}}}};
    FormPaymentConfiguration.normalizeDraft(draft);
    expect(draft.containsKey('paymentMethod'), false);
    expect(draft['payments'], {'bankEnabled': true, 'cashEnabled': false, 'cashInstructions': '', 'providerConnections': {'other': id}});
    final ambiguous = <String,dynamic>{'paymentMethod': 'stripe'};
    FormPaymentConfiguration.normalizeDraft(ambiguous);
    expect(ambiguous['paymentRepairRequired'], true);
    expect(ambiguous['payments']['providerConnections'], isEmpty);
  });
  test('conflicting legacy and modern recipient fails closed', () {
    expect(() => FormPaymentConfiguration.fromJson({'stripeConnectionId': id, 'providerConnections': {'stripe': 'different'}}), throwsFormatException);
  });
  test('namespaced unavailability cannot fall back to legacy recipient or root availability', () {
    final options = FormPaymentOptions.fromJson({'available': ['stripe','bank'], 'bank': {'available': true},
      'configured': {'stripe': true},'recipient': {'connectionId': id},'supportedSurfaces': ['web'],
      'providers': {'stripe': {'configured': true,'available': false,'recipient': {'connectionId': id},'supportedSurfaces': ['web']}}});
    expect(options.availableFor('web'), ['bank']);
  });
  test('cash settings and explicit none survive the actual authoring projection', () {
    final snapshot = FormMetadata.authoringSettingsSnapshot({'payments': {
      'bankEnabled': false, 'cashEnabled': true, 'cashInstructions':'U vstupu', 'providerConnections': <String,String>{}},
      'payment_deadline': {'mode':'none'}});
    expect(snapshot['payments'], {'bankEnabled':false,'cashEnabled':true,'cashInstructions':'U vstupu','providerConnections':<String,String>{}});
    expect(snapshot['payment_deadline'], {'mode':'none'});
    final options = FormPaymentOptions.fromJson({'available':['cash'], 'cash':{'available':true,'instructions':'U vstupu'},'providers':<String,dynamic>{}});
    expect(options.availableFor('web'), ['cash']);
    expect(options.availableFor('embed'), ['cash']);
    expect(options.cashInstructions, 'U vstupu');
    expect(options.cardConfigured, false);
  });

}
