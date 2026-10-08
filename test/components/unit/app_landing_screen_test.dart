import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/occasions_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'switching and clearing landing updates the summary and unique marker',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting();
    int? selected = 1;
    final writes = <Map<String, dynamic>>[];
    await tester.runAsync(() => Supabase.initialize(
        url: 'https://fixture.invalid',
        anonKey: 'fixture',
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            persistSession: false,
            detectSessionInUri: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/set_unit_app_landing')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            writes.add(body);
            expect(body['p_expected_occasion'], selected);
            selected = body['p_occasion'] as int?;
          }
          return http.Response(
              jsonEncode({
                'enabled': true,
                'can_manage': true,
                'occasion_id': selected,
                'occasion_title':
                    selected == null ? null : 'Slunovrat ${2025 + selected!}'
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        })));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Supabase.instance.dispose());
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('cs')],
        startLocale: const Locale('cs'),
        path: 'assets/translations',
        assetLoader: const _Translations(),
        child: Builder(
            builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                theme: ThemeData(fontFamily: 'Roboto'),
                home: RepaintBoundary(
                    key: boundary,
                    child: OccasionsScreen(
                      unit: UnitModel(id: 999),
                      initialOccasions: [
                        for (final id in [1, 2])
                          OccasionModel(
                              id: id,
                              title: 'Slunovrat ${2025 + id}',
                              startTime: DateTime(2025 + id, 6, 18),
                              endTime: DateTime(2025 + id, 6, 20),
                              isOpen: true,
                              isHidden: false,
                              isPromoted: false)
                      ],
                    ))))));
    await tester.pumpAndSettle();
    expect(
        find.text('Aplikace se otevře akcí: Slunovrat 2026'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nastavit jako úvodní akci aplikace'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(
        find.text('Aplikace se otevře akcí: Slunovrat 2027'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    if (const bool.fromEnvironment('LANDING_PREVIEW')) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/app-landing-preview.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Zrušit výběr a zobrazit přehled akcí'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byIcon(Icons.home), findsNothing);
    expect(
        find.text('Aplikace se otevře přehledem karet akcí.'), findsOneWidget);
    expect(writes.length, 2);
    expect(tester.takeException(), isNull);
  });
}
