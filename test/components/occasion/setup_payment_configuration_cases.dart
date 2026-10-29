import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/views/form_variable_symbol_settings.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/setup_payment_configuration.dart';

void main() {
  test(
    'one projection preserves copied policy, source and unrelated form data',
    () {
      final source = <String, dynamic>{
        'data': {
          'variable_symbol': {'type': 'sequence', 'starting_number': 260001},
          'custom': 'keep',
        },
        'fields': [],
        'title': 'Source',
      };
      final draft = <String, dynamic>{
        'formDraft': jsonDecode(jsonEncode(source)),
        'deadline': '3',
        'paymentMethod': 'both',
      };
      final before = jsonEncode(source);
      final projected = SetupPaymentConfiguration.projectForm(draft);
      expect(projected['deadline_duration_seconds'], 259200);
      expect(
        projected['data']['variable_symbol'],
        source['data']!['variable_symbol'],
      );
      SetupPaymentConfiguration.repairPolicy(draft, {
        'type': 'sequence',
        'starting_number': 42,
      });
      expect(jsonEncode(source), before);
      expect(draft['formDraft']['data']['custom'], 'keep');
      expect(SetupPaymentConfiguration.validPolicy(draft), true);
      for (final method in ['bank', 'stripe', 'both']) {
        final fresh = <String, dynamic>{
          'formDraft': {'data': {}},
          'paymentMethod': method,
        };
        expect(SetupPaymentConfiguration.projectForm(fresh)['data'], isEmpty);
        expect(SetupPaymentConfiguration.validPolicy(fresh), true);
      }
    },
  );
  testWidgets(
    'advanced sequence blocks missing and out-of-range values before save',
    (tester) async {
      final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
      addTearDown(logs.dispose);
      final key = GlobalKey<FormState>();
      var policy = <String, dynamic>{'type': 'sequence'};
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: DependencyMaterialBridge(
              child: StatefulBuilder(
                builder: (context, update) => Form(
                  key: key,
                  child: FormVariableSymbolSettings(
                    value: policy,
                    onChanged: (value) => update(() => policy = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(key.currentState!.validate(), false);
      final number = find.byType(TextFormField);
      await tester.enterText(number, '0');
      await tester.pump();
      expect(key.currentState!.validate(), false);
      await tester.enterText(number, '1');
      await tester.pump();
      expect(key.currentState!.validate(), true);
      await tester.enterText(number, '9999999999');
      await tester.pump();
      expect(key.currentState!.validate(), true);
      await tester.enterText(number, '10000000000');
      await tester.pump();
      expect(key.currentState!.validate(), false);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
