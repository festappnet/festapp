import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:fstapp/components/features/deposit_feature.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature_settings_editor.dart';
import 'package:fstapp/components/features/contract_feature.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/editors/contract_feature_defaults.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';

void main() {
  testWidgets(
      'dispatcher edits the original feature and signals its draft scope',
      (tester) async {
    final feature = DepositFeature(code: FeatureConstants.deposit);
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EditorDraftScope(
                onChanged: () => changes++,
                child: Builder(
                    builder: (context) => buildFeatureSettingsEditor(
                        context, feature,
                        occasionId: 42))))));
    await tester.tap(find.byType(RadioListTile<String>).at(1));
    await tester.pump();
    expect(feature.mode, FeatureConstants.depositModeVirtual);
    expect(changes, 1);
  });
  testWidgets('dispatcher carries ticket identity layout scope and callback',
      (tester) async {
    final feature = TicketFeature(code: FeatureConstants.ticket);
    Future<void> save(TicketFeature value) async {
      expect(identical(value, feature), isTrue);
    }

    late Widget result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      result = buildFeatureSettingsEditor(context, feature,
          occasionId: 42, onSaveTicket: save);
      return const SizedBox.shrink();
    })));
    final settings = result as TicketSettings;
    expect(identical(settings.feature, feature), isTrue);
    expect(settings.occasionId, 42);
    expect(settings.key, ValueKey(feature.layout));
    expect(settings.onSave, save);
    await settings.onSave!(feature);
  });
  test(
      'contract defaults preserve entered values dates and transport extraction',
      () {
    final feature = ContractFeature(
        code: FeatureConstants.contract,
        isEnabled: true,
        notes: 'keep',
        tourName: 'manual');
    populateContractFeatureDefaults(feature,
        title: 'title',
        startTime: DateTime(2026, 10, 15, 12),
        endTime: DateTime(2026, 10, 17, 13),
        description: 'Doprava <b>autobusem.</b>');
    expect(feature.tourName, 'manual');
    expect(feature.tourDate, '15. 10. 2026 - 17. 10. 2026');
    expect(feature.numberOfDays, '3');
    expect(feature.transport, 'autobusem');
    expect(feature.notes, 'keep');
    final before = feature.toJson();
    populateContractFeatureDefaults(feature,
        title: 'changed',
        startTime: null,
        endTime: null,
        description: 'Doprava vlakem.');
    expect(feature.toJson(), before);
  });
  testWidgets('unknown feature dispatcher keeps empty editor', (tester) async {
    final feature = Feature.fromJson({'code': 'unknown', 'is_enabled': true});
    late Widget result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      result = buildFeatureSettingsEditor(context, feature, occasionId: 42);
      return const SizedBox.shrink();
    })));
    expect(result, isA<SizedBox>());
  });
}
