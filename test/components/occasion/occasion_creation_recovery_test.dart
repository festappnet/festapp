import 'package:festapp_core/program.dart' as occasion_time;
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_creation_helper.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  late WidgetEnvironmentFixture environment;
  final requests = <Map<String, dynamic>>[];
  setUpAll(() async {
    occasion_time.OccasionTimeContext.initializeTimeZones();
    await initializeDateFormatting('cs');
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>,
    );
    backend = await RootSupabaseFixture.open((request) {
      expect(request.url.path, '/rest/v1/rpc/create_occasion_client_sync_v1');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final config = body['p_config'] as Map<String, dynamic>;
      requests.add(config);
      if (config['link'] == 'qa-formulare') {
        return http.Response(
            jsonEncode({
              'code': '23505',
              'message': 'Public link is already in use',
              'details': null,
              'hint': null,
            }),
            409,
            request: request,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(
          jsonEncode(commandResponseFixture(
            body['p_command_id'] as String,
            data: {
              'occasion': {...config, 'id': 123}
            },
          )),
          200,
          request: request,
          headers: {'content-type': 'application/json'});
    });
  });
  tearDownAll(() => backend.dispose());

  testWidgets('slug conflict preserves draft and allows corrected retry',
      (tester) async {
    OccasionModel? created;
    await environment.pumpWidget(
        tester,
        Builder(
            builder: (context) => MaterialApp(builder: DependencyMaterialBridge.builder,
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
                  home: Builder(
                      builder: (context) => Scaffold(
                              body: TextButton(
                            onPressed: () async {
                              created = await OccasionCreationHelper
                                  .createNewOccasion(
                                      context,
                                      UnitModel(
                                          id: 12,
                                          data: {'timezone': 'Europe/Prague'}),
                                      [],
                                      withoutWizard: true);
                            },
                            child: const Text('Open'),
                          ))),
                )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'QA Kolize události');
    await tester.enterText(fields.at(1), 'qa-formulare');
    await tester.tap(find.text('Vytvořit'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(find.text('Odkaz se již používá.'), findsOneWidget);
    expect(find.text('QA Kolize události'), findsOneWidget);
    expect(created, isNull);
    expect(requests, hasLength(1));
    // Editing another field must not clear a server rejection of this slug.
    await tester.enterText(fields.at(0), 'QA Opravená událost');
    await tester.pump();
    expect(find.text('Odkaz se již používá.'), findsOneWidget);
    await tester.enterText(fields.at(1), 'qa-formulare-recovery');
    await tester.pump();
    await tester.tap(find.text('Vytvořit'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(find.text('Došlo k neočekávané chybě.'), findsNothing);
    expect(created?.id, 123);
    expect(created?.title, 'QA Opravená událost');
    expect(created?.link, 'qa-formulare-recovery');
    expect(requests, hasLength(2));
    expect(requests.last['start_time'], requests.first['start_time']);
    expect(requests.last['end_time'], requests.first['end_time']);
  });
}
