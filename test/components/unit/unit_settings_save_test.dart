import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/unit_settings_screen.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:festapp_core/time.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/unit/views/unit_measurement_settings.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();

  Future<void> toggleMeasurement(WidgetTester tester) async {
    final heading = find.text(FormStrings.measurementTitle).first;
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pumpAndSettle();
  }

  group('organizer settings Save button', () {
    late RootSupabaseFixture backend;
    late Map<String, dynamic> stored;
    final saves = <Map<String, dynamic>>[];
    var updates = 0;
    var rejectSave = false;
    var rejectApproval = false;
    String? approvalError;
    var rejectApprovalRead = false;
    var approvalRequests = 0;
    var approvalReads = 0;
    late Map<String, dynamic> approval;
    final toasts = <MethodCall>[];
    setUpAll(() async {
      tz.OccasionTimeContext.initializeTimeZones();
      PackageInfo.setMockInitialValues(
        appName: 'Festapp',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      backend = await RootSupabaseFixture.open((request) async {
        Object body;
        if (request.url.path.endsWith('/get_unit_for_edit')) {
          body = {'code': 200, 'data': stored};
        } else if (request.url.path.endsWith('/get_payment_method_policy')) {
          body = {
            'organizationId': 1,
            'unitId': 7,
            'revision': 1,
            'preferredMethod': 'bank',
            'methods': {
              for (final method in ['bank', 'cash', 'barion'])
                method: {
                  'id': method,
                  'mode': 'inherit',
                  'inheritedFrom': 'organization',
                  'organizationEnabled': method != 'barion',
                  'policyEnabled': method != 'barion',
                  'configured': method != 'barion',
                  'ready': method != 'barion',
                  'canConfigure': method == 'bank',
                },
            },
          };
        } else if (request.url.path.endsWith(
          '/get_unit_measurement_approval',
        )) {
          approvalReads++;
          if (rejectApprovalRead) {
            return http.Response(
              '{"code":"PGRST202","message":"RPC missing"}',
              404,
              headers: {'content-type': 'application/json'},
            );
          }
          body = {
            ...approval,
            'saved_origins':
                (stored['data'] as Map)['measurement_websites'] ?? <String>[],
          };
        } else if (request.url.path.endsWith(
          '/request_unit_measurement_approval',
        )) {
          expect(jsonDecode(request.body), {'p_unit': 7});
          approvalRequests++;
          if (rejectApproval || approvalError != null) {
            return http.Response(
              jsonEncode({
                'code': 'P0001',
                'message': approvalError ?? 'RPC missing',
              }),
              404,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          approval = {
            ...approval,
            'request_state': 'requested',
            'can_request': false,
            'saved_origins':
                (stored['data'] as Map)['measurement_websites'] ?? <String>[],
            'requested_at': '2026-11-09T12:00:00Z',
            'requested_origins':
                (stored['data'] as Map)['measurement_websites'] ?? <String>[],
          };
          body = approval;
        } else if (request.url.path == '/rest/v1/occasions') {
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/1',
            },
          );
        } else if (request.url.path.endsWith('/save_unit_client_sync_v1')) {
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          saves.add(params);
          if (rejectSave)
            return http.Response(
              jsonEncode({'code': '22023', 'message': 'Settings rejected'}),
              400,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          final payload = params['p_unit_data'] as Map;
          final data = Map<String, dynamic>.from(stored['data'] as Map);
          for (final entry in (payload['settings'] as Map).entries) {
            if (entry.value == null) {
              data.remove(entry.key);
            } else {
              data[entry.key as String] = entry.value;
            }
          }
          stored = {
            ...stored,
            'title': payload['title'],
            'data': data,
            'aggregate_version': (stored['aggregate_version'] as int) + 1,
          };
          body = commandResponseFixture(
            params['p_command_id'] as String,
            data: {'unit': stored, 'version': stored['aggregate_version']},
          );
        } else {
          throw StateError('Unexpected settings request: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
    });
    tearDownAll(() => backend.dispose());
    setUp(() {
      saves.clear();
      updates = 0;
      rejectSave = false;
      rejectApproval = false;
      approvalError = null;
      rejectApprovalRead = false;
      approvalRequests = 0;
      approvalReads = 0;
      approval = {
        'request_state': 'not_requested',
        'can_request': true,
        'saved_origins': <String>[],
        'approved': false,
        'organization_allowed': false,
        'runtime_supported': false,
        'requested_at': null,
      };
      toasts.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (call) async {
              toasts.add(call);
              return true;
            },
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            null,
          );
    });
    final csDefaultTitle =
        ((jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                    as Map)['FeatureFormSettings']
                as Map)['measurementConsentTitle']
            as String;
    for (final (name, replyTo, edited, rejected) in [
      (
        'set Reply-To',
        'poradatel@example.invalid',
        '<script>window.savedMeasurement = 2;</script>',
        false,
      ),
      (
        'empty Reply-To',
        '',
        '<script>window.savedMeasurement = 2;</script>',
        false,
      ),
      ('restore default', 'poradatel@example.invalid', '', false),
      ('cleared code', 'poradatel@example.invalid', '', false),
      ('enable consent bridge', 'poradatel@example.invalid', '', false),
      ('disable consent bridge', 'poradatel@example.invalid', '', false),
      (
        'rejected save',
        'poradatel@example.invalid',
        '<script>window.savedMeasurement = 2;</script>',
        true,
      ),
    ]) {
      testWidgets('tracking code Save button: $name', (tester) async {
        rejectSave = rejected;
        stored = {
          'id': 7,
          'organization': 1,
          'title': 'Slavnostní ples',
          'aggregate_version': 4,
          'data': {
            'reply_to': replyTo,
            'timezone': 'Europe/Prague',
            'measurement_enabled': false,
            if (name == 'disable consent bridge')
              'measurement_consent_bridge': true,
            'measurement_privacy_url': 'https://organizer.example/privacy',
            'measurement_scripts':
                '<script>window.savedMeasurement = 1;</script>',
            // A deliberate override identical to today's default must survive
            // saving other fields; an unset text must stay unset (null).
            'measurement_consent_title': csDefaultTitle,
          },
        };
        final unit = UnitModel.fromJson(Map<String, dynamic>.from(stored));
        final rights = RightsContextFixture(
          context: OccasionLinkModel.fromJson({
            'code': 200,
            'unit': {'id': 7},
            'organization': {'FORM_MEASUREMENT_ENABLED': true},
            'capabilities': {'unit.settings.write': true},
          }),
        );
        addTearDown(rights.dispose);
        final environment = WidgetEnvironmentFixture(
          locale: const Locale('cs'),
          translations: jsonDecode(
            File('assets/translations/cs.json').readAsStringSync(),
          ) as Map<String, dynamic>,
        );
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: UnitSettingsScreen(
              unit: unit,
              onUnitUpdated: () => updates++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(UnitMeasurementSettings),
          findsNothing,
          reason: 'Measurement starts collapsed',
        );
        final payments = find.byKey(
          const PageStorageKey('unit-payment-settings'),
        );
        expect(payments, findsOneWidget);
        expect(
          find.byKey(const ValueKey('payment-policy-bank')),
          findsNothing,
          reason: 'Payment details start collapsed',
        );
        await tester.ensureVisible(payments);
        await tester.tap(
          find.descendant(of: payments, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('payment-policy-bank')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('payment-policy-barion')),
          findsNothing,
        );
        await tester.tap(
          find.descendant(of: payments, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        await toggleMeasurement(tester);
        await tester.ensureVisible(find.text(FormStrings.measurementAdvanced));
        await tester.tap(find.text(FormStrings.measurementAdvanced));
        await tester.pumpAndSettle();
        final settings = tester.widget<UnitMeasurementSettings>(
          find.byType(UnitMeasurementSettings),
        );
        if (name == 'restore default') {
          final restore = find
              .widgetWithText(
                TextButton,
                FormStrings.measurementConsentRestoreDefault,
              )
              .first;
          await tester.ensureVisible(restore);
          await tester.tap(restore);
          await tester.pumpAndSettle();
          expect(settings.consentTitleController.text, csDefaultTitle);
        }
        expect(settings.consentBridge, name == 'disable consent bridge');
        if (name.contains('consent bridge')) {
          settings.onConsentBridgeChanged!(name == 'enable consent bridge');
          await tester.pumpAndSettle();
        }
        final code = find.byWidgetPredicate(
          (w) =>
              w is TextFormField && w.controller == settings.scriptsController,
        );
        await tester.ensureVisible(code);
        await tester.enterText(code, edited);
        // Collapse with an unsaved draft: Save must still validate and persist it.
        await toggleMeasurement(tester);
        expect(find.byType(UnitMeasurementSettings), findsNothing);
        expect(settings.scriptsController.text, edited);
        final save = find.widgetWithText(ElevatedButton, CommonStrings.save);
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          saves,
          hasLength(1),
          reason: 'the Save button must dispatch the changed settings',
        );
        expect(saves.single['p_expected_version'], 4);
        expect(
          ((saves.single['p_unit_data'] as Map)['settings']
              as Map)['measurement_consent_bridge'],
          name == 'enable consent bridge',
        );
        expect(
          ((saves.single['p_unit_data'] as Map)['settings'] as Map)['reply_to'],
          replyTo.isEmpty ? null : replyTo,
        );
        expect(
          ((saves.single['p_unit_data'] as Map)['settings']
              as Map)['measurement_scripts'],
          edited.isEmpty ? null : edited,
        );
        final savedSettings =
            (saves.single['p_unit_data'] as Map)['settings'] as Map;
        expect(
          savedSettings['measurement_consent_title'],
          name == 'restore default' ? isNull : csDefaultTitle,
        );
        expect(savedSettings['measurement_consent_text'], isNull);
        final expected = rejected
            ? '<script>window.savedMeasurement = 1;</script>'
            : edited.isEmpty
            ? null
            : edited;
        expect((stored['data'] as Map)['measurement_scripts'], expected);
        expect(unit.data?['measurement_scripts'], expected);
        expect(unit.aggregateVersion, rejected ? 4 : 5);
        expect(updates, rejected ? 0 : 1);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    for (final failure in [
      'none',
      'request RPC',
      'read RPC',
      'measurement_request_no_recipient',
      'measurement_notification_origin_missing',
    ]) {
      testWidgets('measurement approval persists and handles $failure', (
        tester,
      ) async {
        approvalError = failure.startsWith('measurement_') ? failure : null;
        rejectApproval = failure == 'request RPC' || approvalError != null;
        rejectApprovalRead = failure == 'read RPC';
        stored = {
          'id': 7,
          'organization': 1,
          'title': 'Slavnostní ples',
          'aggregate_version': 4,
          'data': {'measurement_enabled': true, 'timezone': 'Europe/Prague'},
        };
        final rights = RightsContextFixture(
          context: OccasionLinkModel.fromJson({
            'code': 200,
            'unit': {'id': 7},
            'organization': {'FORM_MEASUREMENT_ENABLED': true},
            'capabilities': {'unit.settings.write': true},
          }),
        );
        addTearDown(rights.dispose);
        final environment = WidgetEnvironmentFixture(
          locale: const Locale('cs'),
          translations: jsonDecode(
            File('assets/translations/cs.json').readAsStringSync(),
          ) as Map<String, dynamic>,
        );
        Future<void> load() async {
          await environment.pumpWidget(
            tester,
            MaterialApp(
              builder: DependencyMaterialBridge.builder,
              home: UnitSettingsScreen(
                unit: UnitModel.fromJson(stored),
                onUnitUpdated: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          await toggleMeasurement(tester);
        }

        await load();
        final button = find.widgetWithText(
          OutlinedButton,
          FormStrings.measurementApprovalRequest,
        );
        if (rejectApprovalRead) {
          expect(button, findsNothing);
          expect(toasts, isNotEmpty);
          final retry = find.widgetWithText(
            OutlinedButton,
            CommonStrings.retry,
          );
          await tester.ensureVisible(retry);
          // A repeated failure must leave another attempt available.
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(approvalReads, 2);
          expect(tester.widget<OutlinedButton>(retry).onPressed, isNotNull);
          expect(approvalRequests, 0);
          rejectApprovalRead = false;
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(approvalReads, 3);
          expect(retry, findsNothing);
        }
        if (failure == 'none') {
          final settings = tester.widget<UnitMeasurementSettings>(
            find.byType(UnitMeasurementSettings),
          );
          settings.websitesController!.text = 'not a website';
          await toggleMeasurement(tester);
          final invalidSave = find.widgetWithText(
            ElevatedButton,
            CommonStrings.save,
          );
          await tester.ensureVisible(invalidSave);
          await tester.tap(invalidSave);
          await tester.pumpAndSettle();
          expect(saves, isEmpty);
          expect(
            find.byType(UnitMeasurementSettings),
            findsOneWidget,
            reason: 'Saving must reveal a collapsed invalid field',
          );
          expect(
            find.text(FormStrings.measurementWebsitesInvalid),
            findsOneWidget,
          );
          settings.websitesController!.text = 'https://poradatel.example';
          await tester.pump();
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
          final save = find.widgetWithText(ElevatedButton, CommonStrings.save);
          await tester.ensureVisible(save);
          rejectSave = true;
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(approvalRequests, 0);
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
          expect((stored['data'] as Map)['measurement_websites'], isNull);
          rejectSave = false;
          await tester.tap(save);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(approvalRequests, 1);
        if (failure == 'none') {
          expect(saves, hasLength(2));
          expect((stored['data'] as Map)['measurement_websites'], [
            'https://poradatel.example',
          ]);
        }
        expect(
          tester.widget<OutlinedButton>(button).onPressed == null,
          !rejectApproval,
        );
        if (rejectApproval) {
          expect(toasts, isNotEmpty);
          if (approvalError != null) {
            final message = approvalError == 'measurement_request_no_recipient'
                ? FormStrings.measurementRequestNoRecipient
                : FormStrings.measurementNotificationOriginMissing;
            expect(toasts.last.arguments.toString(), contains(message));
          }
        } else {
          expect(
            find.textContaining('Čeká na potvrzení platformou.'),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await load();
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
          expect(
            find.textContaining('Čeká na potvrzení platformou.'),
            findsOneWidget,
          );
          expect(
            approvalRequests,
            1,
            reason: 'reload must read the request without resending',
          );
        }
        expect(find.text(FormStrings.gtmContainer), findsOneWidget);
        expect(find.text(FormStrings.measurementAdvanced), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}
