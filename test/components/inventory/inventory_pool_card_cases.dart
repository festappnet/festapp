import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/inventory/models/inventory_pools_list_bundle.dart';
import 'package:fstapp/components/inventory/views/inventory_pool_card.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
  });
  testWidgetsWithEnvironment(() => environment,
      'inventory card uses SQL supply and each context own allocation counts',
      (tester) async {
    final bundle = InventoryPoolsListBundle.fromJson({
      'occasion': {'id': 7},
      'pools': [
        {
          'id': 1,
          'occasion': 7,
          'title': 'Stock',
          'sellable_capacity': 80,
          'resource_capacity': 100
        }
      ],
      'inventory_contexts': [
        {
          'id': 2,
          'inventory_pool': 1,
          'title': 'First',
          'physical_count': 20,
          'allocated_count': 5,
          'unassigned_count': 2,
          'held_count': 3
        },
        {
          'id': 3,
          'inventory_pool': 1,
          'title': 'Second',
          'physical_count': 30,
          'allocated_count': 1,
          'unassigned_count': 0,
          'held_count': 0
        },
      ],
    });
    expect(
        bundle.contextStocks.first.context.inventoryPool, bundle.pools.single);
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
                body: SizedBox(
                    width: 900,
                    child: InventoryPoolCard(
                        pool: bundle.pools.single,
                        contexts: bundle.contextStocks,
                        onTap: () {})))));
    expect(find.text('5 / 20'), findsOneWidget);
    expect(find.text('1 / 30'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
