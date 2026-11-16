import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/time.dart' as tz;
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_settings_editor.dart';
import 'package:fstapp/components/forms/customer_order_changes.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/customer_self_service_settings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(tz.OccasionTimeContext.initializeTimeZones);
  final helpEnvironment = WidgetEnvironmentFixture(
    locale: const Locale('en'),
    translations: jsonDecode(
      File('assets/translations/en.json').readAsStringSync(),
    ),
  );
  testWidgetsWithEnvironment(
    () => helpEnvironment,
    'self-service configure dialog explains where form rules are configured',
    (tester) async {
      final feature = SimpleFeature(
        code: FeatureConstants.customerSelfService,
        isEnabled: true,
      );
      await helpEnvironment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  buildFeatureSettingsEditor(context, feature, occasionId: 7),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Settings - Customer self-service'),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );
  for (final enabled in [false, true]) {
    final environment = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: jsonDecode(
        File('assets/translations/en.json').readAsStringSync(),
      ),
    );
    testWidgetsWithEnvironment(
      () => environment,
      'self-service feature $enabled exposes setup state without enabling customer operations',
      (tester) async {
        final rights = RightsContextFixture(
          context: OccasionLinkModel(
            occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
                SimpleFeature(
                  code: FeatureConstants.customerSelfService,
                  isEnabled: enabled,
                ),
              ],
            ),
          ),
        );
        addTearDown(rights.dispose);
        final form = FormEditorDraft(id: 1, occasionId: 7);
        if (enabled) {
          form.definition = form.definition.copyWith(
            customerSelfService: {
              'policy': {
                'move': {'enabled': true, 'targets': <dynamic>[]},
              },
            },
          );
        }
        final originalPolicy = jsonEncode(form.definition.customerSelfService);
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: SingleChildScrollView(
                child: CustomerSelfServiceSettings(
                  form: form,
                  canEdit: true,
                  onChanged: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Customer self-service'), findsOneWidget);
        expect(
          find.text(customerChangeText(enabled ? 'notConfigured' : 'offHelp')),
          findsOneWidget,
        );
        expect(form.customerPolicyDirty, isFalse);
        expect(jsonEncode(form.definition.customerSelfService), originalPolicy);
        expect(find.text('CustomerSelfService.move'), findsNothing);
        expect(find.text('CustomerSelfService.termHelp'), findsNothing);
        expect(find.byType(TimeDatePicker), findsNothing);
        if (!enabled) {
          await tester.tap(find.text('Customer self-service'));
          await tester.pumpAndSettle();
        }
        final cancellation = find.widgetWithText(
          SwitchListTile,
          customerChangeText('cancel'),
        );
        final control = tester.widget<SwitchListTile>(cancellation);
        expect(control.value, isFalse);
        if (enabled) {
          await tester.ensureVisible(cancellation);
          await tester.tap(cancellation);
          await tester.pumpAndSettle();
          expect(form.customerPolicyDirty, isTrue);
          final policy = form.toEditedJson()['customer_self_service'] as Map;
          expect(policy['cancel']['enabled'], isTrue);
          expect(policy['cancel']['mode'], 'approval_required');
          expect(policy['cancel']['refund_mode'], 'none');
          expect(policy.containsKey('move'), isFalse);
          expect(find.byType(TimeDatePicker), findsOneWidget);
          final deadline = tester.widget<TimeDatePicker>(
            find.byType(TimeDatePicker),
          );
          expect(deadline.dateLabel, customerChangeText('deadlineDate'));
          expect(deadline.timeLabel, customerChangeText('deadlineTime'));
          expect(
            find.text(customerChangeText('configuredHelp')),
            findsOneWidget,
          );
        } else {
          expect(control.onChanged, isNull);
        }
      },
    );
  }
}
