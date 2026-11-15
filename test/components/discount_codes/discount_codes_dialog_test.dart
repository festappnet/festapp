import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/discount_codes/discount_codes_dialog.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

// Full catalog owns a separate test isolate from untranslated default suites.
void main() {
  WidgetEnvironmentFixture.register();
  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'discount manager saves and refreshes server values at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previous = RightsService.occasionLinkModel;
        addTearDown(
          () => RightsService.occasionLinkModelNotifier.value = previous,
        );
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [
              SimpleFeature(
                code: FeatureConstants.discountCodes,
                isEnabled: true,
              ),
            ],
          ),
          capabilities: {AuthorizationCapabilities.ordersWrite: true},
        );
        var reads = 0;
        var saved = false;
        final client = (await tester.runAsync(
          () async => SupabaseClient(
            'https://fixture.invalid',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
              if (request.url.path.endsWith('/save_discount_code')) {
                saved = true;
                return http.Response(
                  '{}',
                  200,
                  headers: {'content-type': 'application/json'},
                  request: request,
                );
              }
              expect(request.url.path.endsWith('/list_discount_codes'), true);
              reads++;
              return http.Response(
                jsonEncode([
                  {
                    'id': 1,
                    'normalized_code': 'SLEVA30',
                    'kind': 'percent',
                    'value': saved ? 2500 : 3000,
                    'is_active': true,
                    'uses': 0,
                    'discountTotals': {},
                    'revision': saved ? 2 : 1,
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }),
          ),
        ))!;
        addTearDown(() => tester.runAsync(client.dispose));
        final environment = WidgetEnvironmentFixture(
          locale: const Locale('cs'),
          translations: jsonDecode(
            File('assets/translations/cs.json').readAsStringSync(),
          ),
        );
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => DiscountCodesDialog(
                      occasion: 1,
                      client: client,
                      bundle: ProductsEditBundle(
                        products: [],
                        productTypes: [],
                        inventoryPools: [],
                        inventoryContexts: [],
                        forms: [],
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(AppAlertDialog), findsOneWidget);
        expect(
          find.text('Celková přiznaná sleva: 0'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join('|'),
        );
        await tester.tap(find.text('SLEVA30'));
        await tester.pumpAndSettle();
        expect(find.byType(AppDialogActions), findsNWidgets(2));
        final save = find.widgetWithText(FilledButton, 'Uložit');
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved, true);
        expect(reads, 2);
        expect(find.byType(AppAlertDialog), findsOneWidget);
        expect(find.textContaining('25 %'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
