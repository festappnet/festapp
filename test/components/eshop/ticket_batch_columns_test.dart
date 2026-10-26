import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/eshop/tickets_tab.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/data_services/rights_service.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class _Router extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
            path: '/:${AppRouter.linkFormatted}',
            page: PageInfo('TicketsFixture',
                builder: (_) => const Scaffold(body: TicketsTab())))
      ];
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
    await Supabase.initialize(
        url: 'https://fixture.invalid',
        publishableKey: 'fixture',
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false, localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                for (final key in [
                  'orders',
                  'spots',
                  'products',
                  'product_types',
                  'tickets',
                  'payment_info',
                  'forms',
                  'order_product_ticket',
                  'orders_history',
                  'users'
                ])
                  key: <dynamic>[]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request)));
  });
  tearDownAll(() => Supabase.instance.dispose());
  final variants = <String, Map<String, dynamic>>{
    'legacy occasion without batch setting': {
      'code': 'ticket',
      'is_enabled': true
    },
    'batch feature explicitly disabled': {
      'code': 'ticket',
      'is_enabled': true,
      'pregenerated_tickets': false
    },
    'ticket feature disabled despite saved opt-in': {
      'code': 'ticket',
      'is_enabled': false,
      'pregenerated_tickets': true
    },
    'batch feature enabled': {
      'code': 'ticket',
      'is_enabled': true,
      'pregenerated_tickets': true
    },
  };
  for (final entry in variants.entries) {
    testWidgetsWithEnvironment(
        () => environment, 'actual ticket grid columns: ${entry.key}',
        (tester) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      final router = _Router();
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              id: 1,
              link: 'fixture',
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [Feature.fromJson(entry.value)]));
      addTearDown(() {
        RightsService.occasionLinkModelNotifier.value = previous;
        router.dispose();
      });
      await environment.pumpWidget(
          tester,
          MaterialApp.router(builder: DependencyMaterialBridge.builder,
              routerConfig: router.config(
                  deepLinkBuilder: (_) => DeepLink.path('/fixture'))));
      await tester.pumpAndSettle();
      final grid = tester.widget<SingleTableDataGrid<TicketModel>>(
          find.byType(SingleTableDataGrid<TicketModel>));
      final fields = grid.controller.columns.map((c) => c.field).toSet();
      final expected = entry.value['is_enabled'] == true &&
          entry.value['pregenerated_tickets'] == true;
      for (final field in [
        EshopColumnIds.TICKET_ORIGIN,
        EshopColumnIds.TICKET_BATCH,
        EshopColumnIds.TICKET_SALE_STATE
      ]) {
        expect(fields.contains(field), expected,
            reason: '$field is relevant only with explicit batch opt-in');
      }
      expect(
          fields,
          containsAll(
              [EshopColumnIds.ORDER_SYMBOL, EshopColumnIds.TICKET_STATE]));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
