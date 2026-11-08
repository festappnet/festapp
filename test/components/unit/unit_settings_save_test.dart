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

  group('organizer settings Save button', () {
    late RootSupabaseFixture backend;
    late Map<String, dynamic> stored;
    final saves = <Map<String, dynamic>>[];
    var updates = 0;
    var rejectSave = false;
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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (_) async => true,
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            null,
          );
    });
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
      ('cleared code', 'poradatel@example.invalid', '', false),
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
          'title': 'Slavnostní ples',
          'aggregate_version': 4,
          'data': {
            'reply_to': replyTo,
            'timezone': 'Europe/Prague',
            'measurement_enabled': false,
            'measurement_privacy_url': 'https://organizer.example/privacy',
            'measurement_scripts':
                '<script>window.savedMeasurement = 1;</script>',
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
        await tester.ensureVisible(find.text(FormStrings.measurementTitle));
        await tester.tap(find.text(FormStrings.measurementTitle));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(FormStrings.measurementAdvanced));
        await tester.tap(find.text(FormStrings.measurementAdvanced));
        await tester.pumpAndSettle();
        final settings = tester.widget<UnitMeasurementSettings>(
          find.byType(UnitMeasurementSettings),
        );
        final code = find.byWidgetPredicate(
          (w) =>
              w is TextFormField && w.controller == settings.scriptsController,
        );
        await tester.ensureVisible(code);
        await tester.enterText(code, edited);
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
          ((saves.single['p_unit_data'] as Map)['settings'] as Map)['reply_to'],
          replyTo.isEmpty ? null : replyTo,
        );
        expect(
          ((saves.single['p_unit_data'] as Map)['settings']
              as Map)['measurement_scripts'],
          edited.isEmpty ? null : edited,
        );
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
  });
}
