import 'package:fstapp/components/payments/payment_method_cards.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

import 'package:festapp_core/forms.dart';

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

late ValueNotifier<({int accountId, int revision})> _bankChanges;
void main() {
  test('disabled bank projection omits recipient writes and preserves its stored identity', () {
    final draft =
        FormEditorDraft(
            bankAccountId: 42,
            data: {
              'payments': {'bankEnabled': true},
            },
          )
          ..paymentMethodPolicy = {
            'methods': {
              'bank': {'policyEnabled': false},
            },
          };
    expect(draft.toEditedJson().containsKey('bank_account'), isFalse);
    expect(draft.definition.bankAccountId, 42);
  });
  setUp(() {
    _bankChanges = ValueNotifier((accountId: 0, revision: 0));
    addTearDown(_bankChanges.dispose);
  });
  WidgetEnvironmentFixture.register();
  setUpAll(
    () => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    ),
  );

  for (final unitEnabled in [true, false]) {
    for (final canMeasure in [true, false]) {
      testWidgetsWithEnvironment(
        () => _environment,
        'form measurement owns only enabled with unit=$unitEnabled and permission=$canMeasure',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 4000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          void rights(bool measurement) {
            RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
              unit: UnitModel(
                id: 7,
                data: {'measurement_enabled': unitEnabled},
              ),
              capabilities: {
                AuthorizationCapabilities.formsWrite: true,
                AuthorizationCapabilities.unitSettingsWrite: measurement,
                AuthorizationCapabilities.formsMeasurementWrite: measurement,
                AuthorizationCapabilities.ordersWrite: true,
                AuthorizationCapabilities.occasionsWrite: true,
              },
              occasionUser: OccasionUserModel(isEditor: true),
              occasion: OccasionModel(
                isOpen: true,
                isHidden: false,
                isPromoted: false,
                features: [FormFeature(code: 'form')],
              ),
            );
          }

          rights(canMeasure);
          addTearDown(
            () => RightsService.occasionLinkModelNotifier.value = null,
          );
          final changes = ValueNotifier((accountId: 0, revision: 0));
          addTearDown(changes.dispose);
          final form = FormEditorDraft(
            link: 'test',
            title: 'Letní koncert',
            data: {
              'analytics': {'enabled': false},
            },
          );
          form.definition = form.definition.copyWith(
            measurementStatus: {
              'organization_enabled': true,
              'unit_enabled': unitEnabled,
              'runtime_supported': false,
            },
          );
          final saved = <Map<String, dynamic>?>[];
          await _environment.pumpWidget(
            tester,
            MaterialApp(
              builder: DependencyMaterialBridge.builder,
              home: FormSettingsContent(
                bankConnectionChanges: changes,
                formLink: 'test',
                loadBundle: (_) async => FormEditBundle(
                  form: form,
                  productTypes: [],
                  products: [],
                  availableBankAccounts: [],
                ),
                saveForm: (value) async {
                  saved.add(value.definition.data);
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final toggle = find.widgetWithText(
            SwitchListTile,
            FormStrings.measurementEnabled,
          );
          expect(toggle, findsNothing);
          await tester.ensureVisible(find.text(FormStrings.measurementTitle));
          await tester.tap(find.text(FormStrings.measurementTitle));
          await tester.pumpAndSettle();
          expect(tester.widget<SwitchListTile>(toggle).value, false);
          expect(
            find.text(FormStrings.measurementFormUnitBlocked),
            unitEnabled ? findsNothing : findsOneWidget,
          );
          expect(
            find.text(FormStrings.measurementOpenUnitSettings),
            canMeasure ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(FormStrings.measurementAskUnitManager),
            canMeasure ? findsNothing : findsOneWidget,
          );
          expect(
            tester.widget<SwitchListTile>(toggle).onChanged == null,
            !canMeasure,
          );
          expect(
            find.widgetWithText(TextFormField, FormStrings.gtmContainer),
            findsNothing,
          );
          expect(
            find.widgetWithText(TextFormField, FormStrings.measurementScripts),
            findsNothing,
          );
          Future<void> save() async {
            await tester
                .widget<EditorActionBar>(find.byType(EditorActionBar))
                .onSave();
            await tester.pumpAndSettle();
          }

          if (canMeasure) {
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            // Platform policy and runtime gates show as one plain reason.
            expect(
              find.text(FormStrings.measurementPlatformBlocked),
              findsOneWidget,
            );
            await save();
            expect(saved.last?['analytics'], {'enabled': true});
            expect(RightsService.currentUnit()?.data, {
              'measurement_enabled': unitEnabled,
            });
            await tester.ensureVisible(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            await save();
            expect(saved.last?['analytics'], {'enabled': false});
            rights(false);
            await tester.pumpAndSettle();
            expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
            final title = find.widgetWithText(
              TextFormField,
              FormStrings.labelFormTitle,
            );
            await tester.ensureVisible(title);
            await tester.enterText(title, 'Podzimní koncert');
            await save();
            expect(saved.last?['analytics'], {'enabled': false});
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final blocked in ['organization_enabled']) {
    testWidgetsWithEnvironment(
      () => _environment,
      'hidden measurement preserves form choice when $blocked is false',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          capabilities: {
            AuthorizationCapabilities.formsWrite: true,
            AuthorizationCapabilities.formsMeasurementWrite: true,
          },
          occasionUser: OccasionUserModel(isEditor: true),
          occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [FormFeature(code: 'form')],
          ),
        );
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        final changes = ValueNotifier((accountId: 0, revision: 0));
        addTearDown(changes.dispose);
        final form = FormEditorDraft(
          link: 'test',
          title: 'Letní koncert',
          data: {
            'analytics': {'enabled': true},
          },
        );
        form.definition = form.definition.copyWith(
          measurementStatus: {
            'organization_enabled': true,
            'unit_enabled': true,
            blocked: false,
          },
        );
        Map<String, dynamic>? saved;
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: FormSettingsContent(
              bankConnectionChanges: changes,
              formLink: 'test',
              loadBundle: (_) async => FormEditBundle(
                form: form,
                productTypes: [],
                products: [],
                availableBankAccounts: [],
              ),
              saveForm: (value) async {
                saved = value.definition.data;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SwitchListTile, FormStrings.measurementEnabled),
          findsNothing,
        );
        final title = find.widgetWithText(
          TextFormField,
          FormStrings.labelFormTitle,
        );
        await tester.enterText(title, 'Podzimní koncert');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(saved?['analytics'], {'enabled': true});
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (name, manager, formOn, unitOn, reasons, warned) in [
    ('missing link', true, true, true, ['no_privacy_policy'], true),
    ('form editor only', false, true, true, ['no_privacy_policy'], true),
    ('form off', true, false, true, ['disabled', 'no_privacy_policy'], false),
    (
      'unit off',
      true,
      true,
      false,
      ['unit_disabled', 'no_privacy_policy'],
      true,
    ),
    (
      'no destination',
      true,
      true,
      true,
      ['no_destination', 'no_privacy_policy'],
      true,
    ),
    ('platform block editor', false, true, true, ['platform_block'], false),
    ('unsaved enable', true, false, true, <String>[], false),
    ('unknown block', true, true, true, ['future_block'], false),
    ('link present', true, true, true, <String>[], false),
  ]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'collapsed measurement privacy warning: $name',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          capabilities: {
            AuthorizationCapabilities.formsWrite: true,
            AuthorizationCapabilities.unitSettingsWrite: manager,
            AuthorizationCapabilities.formsMeasurementWrite: manager,
          },
          occasionUser: OccasionUserModel(isEditor: true),
          occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [FormFeature(code: 'form')],
          ),
        );
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        final changes = ValueNotifier((accountId: 0, revision: 0));
        addTearDown(changes.dispose);
        final form = FormEditorDraft(
          link: 'test',
          title: 'Letní koncert',
          data: {
            'analytics': {'enabled': formOn},
          },
        );
        form.definition = form.definition.copyWith(
          measurementStatus: {
            'organization_enabled': true,
            'unit_enabled': unitOn,
            'blocked_reasons': reasons,
            'eligible': reasons.isEmpty,
            'organization_allowed': name != 'platform block editor',
            'runtime_supported': name != 'platform block editor',
          },
        );
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: FormSettingsContent(
              bankConnectionChanges: changes,
              formLink: 'test',
              loadBundle: (_) async => FormEditBundle(
                form: form,
                productTypes: [],
                products: [],
                availableBankAccounts: [],
              ),
              saveForm: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SwitchListTile, FormStrings.measurementEnabled),
          findsNothing,
        );
        await tester.ensureVisible(find.text(FormStrings.measurementTitle));
        await tester.tap(find.text(FormStrings.measurementTitle));
        await tester.pumpAndSettle();
        expect(
          find.text(FormStrings.measurementNoPrivacyPolicy),
          warned ? findsOneWidget : findsNothing,
        );
        await tester.ensureVisible(find.text(FormStrings.measurementTitle));
        expect(
          find.text(FormStrings.measurementReady),
          reasons.isEmpty && formOn ? findsOneWidget : findsNothing,
        );
        if (name == 'platform block editor') {
          expect(
            find.text(FormStrings.measurementPlatformBlocked),
            findsNothing,
          );
          expect(
            find.text(FormStrings.measurementAskUnitManager),
            findsWidgets,
          );
        }
        if (name == 'unsaved enable') {
          final toggle = find.widgetWithText(
            SwitchListTile,
            FormStrings.measurementEnabled,
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(find.text(FormStrings.measurementReady), findsNothing);
        }
        if (formOn && reasons.contains('no_privacy_policy')) {
          expect(
            find.text(FormStrings.measurementNoPrivacyPolicy),
            findsWidgets,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final override in [null, false, true]) {
    testWidgetsWithEnvironment(
      () => _environment,
      'preserves reminder override $override on unrelated save and can restore inheritance',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          capabilities: {
            AuthorizationCapabilities.formsWrite: true,
            AuthorizationCapabilities.ordersWrite: true,
            AuthorizationCapabilities.occasionsWrite: true,
          },
          occasionUser: OccasionUserModel(isEditor: true),
          occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [
              FormFeature(
                code: 'form',
                reminderIsEnabled: true,
                reminderIntervalSeconds: 86400,
                deadlineDurationSeconds: 604800,
              ),
            ],
          ),
        );
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        final form = FormEditorDraft(
          link: 'test',
          title: 'Original',
          data: {
            if (override != null)
              FormDefinition.metaIsReminderEnabled: override,
          },
        );
        var saves = 0;
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: FormSettingsContent(
              bankConnectionChanges: _bankChanges,
              formLink: 'test',
              loadBundle: (_) async => FormEditBundle(
                form: form,
                productTypes: [],
                products: [],
                availableBankAccounts: [],
              ),
              saveForm: (_) async {
                saves++;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditorActionBar>(find.byType(EditorActionBar))
              .hasChanges,
          isFalse,
        );
        final title = find.widgetWithText(
          TextFormField,
          FormStrings.labelFormTitle,
        );
        await tester.enterText(title, 'Changed');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(
          form.definition.data?[FormDefinition.metaIsReminderEnabled],
          override,
        );
        expect(
          form.definition.data!.containsKey(
            FormDefinition.metaIsReminderEnabled,
          ),
          override != null,
        );
        expect(form.definition.deadlineDurationSeconds, isNull);
        expect(
          form.definition.data!.containsKey(
            FormDefinition.metaReminderIntervalSeconds,
          ),
          isFalse,
        );
        if (override != null) {
          final reminder = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == FormStrings.labelEnableReminders,
          );
          tester.widget<DropdownButtonFormField<String>>(reminder).onChanged!(
            'inherit',
          );
          await tester.pumpAndSettle();
          await tester
              .widget<EditorActionBar>(find.byType(EditorActionBar))
              .onSave();
          await tester.pumpAndSettle();
          expect(
            form.definition.data!.containsKey(
              FormDefinition.metaIsReminderEnabled,
            ),
            isFalse,
          );
        }
        final interval = find.widgetWithText(
          TextFormField,
          FormStrings.labelReminderInterval,
        );
        final deadlineMode = find.byKey(
          const ValueKey('form-payment-deadline-mode'),
        );
        tester.widget<DropdownButtonFormField<String>>(deadlineMode).onChanged!(
          'custom',
        );
        await tester.pumpAndSettle();
        final deadline = find.widgetWithText(
          TextFormField,
          FormStrings.labelDeadlineDays,
        );
        await tester.enterText(interval, '2');
        await tester.enterText(deadline, '4');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(
          form.definition.data![FormDefinition.metaReminderIntervalSeconds],
          172800,
        );
        expect(form.definition.deadlineDurationSeconds, 345600);
        await tester.enterText(deadline, '0');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(form.definition.deadlineDurationSeconds, 0);
        await tester.enterText(interval, '');
        tester.widget<DropdownButtonFormField<String>>(deadlineMode).onChanged!(
          'none',
        );
        await tester.pumpAndSettle();
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(form.definition.deadlineDurationSeconds, isNull);
        expect(form.definition.data?['payment_deadline'], {'mode': 'none'});
        tester.widget<DropdownButtonFormField<String>>(deadlineMode).onChanged!(
          'inherit',
        );
        await tester.pumpAndSettle();
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(
          form.definition.data!.containsKey(
            FormDefinition.metaReminderIntervalSeconds,
          ),
          isFalse,
        );
        expect(form.definition.deadlineDurationSeconds, isNull);
        if (override == null) {
          tester
              .widget<PaymentMethodCards>(find.byType(PaymentMethodCards))
              .onChanged(FormPaymentMethod.cash);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(
              TextFormField,
              PaymentMethodStrings.text('cashInstructions'),
            ),
            'Uhraďte u vstupu.',
          );
          await tester
              .widget<EditorActionBar>(find.byType(EditorActionBar))
              .onSave();
          await tester.pumpAndSettle();
          final settings = form.toEditedJson()['settings'] as Map;
          expect(settings['payments'], {
            'bankEnabled': false,
            'cashEnabled': true,
            'cashInstructions': 'Uhraďte u vstupu.',
            'providerConnections': <String, String>{},
          });
          expect(settings['payment_deadline'], {'mode': 'none'});
          expect(form.definition.deadlineDurationSeconds, isNull);
          expect(
            find.text(PaymentMethodStrings.reason('not_configured')),
            findsNothing,
          );
        }
        await _environment.pumpWidget(tester, const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
