import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/services/exception_handler.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:festapp_core/eshop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';
import 'package:fstapp/components/eshop/product_grid_record.dart';
import 'package:fstapp/components/single_data_grid/data_grid_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('admin sales columns retain the canonical SQL counts through an edit', (tester) async {
    final product = ProductModel.fromJson({
      'id': 7, 'title': 'Admission', 'ordered_count': 4,
      'paid_count': 2, 'sent_count': 1, 'purchased_count': 3,
      'form_ids': [9],
    }).copyWith(formTitles: 'Registration');
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      final record = ProductGridRecord(product: product,
          commands: _Commands((_) {}), guard: ExceptionHandler.guardVoid);
      final row = record.toTrinaRow(context);
      expect(row.cells[EshopColumnIds.PRODUCT_PAID_COUNT]!.value, 3);
      expect(row.cells[EshopColumnIds.PRODUCT_ORDERED_COUNT]!.value, 4);
      expect(row.cells[EshopColumnIds.PRODUCT_USED_IN_FORMS]!.value, 'Registration');
      final edited = ProductGridRecord.fromPlutoJson({
        for (final entry in row.cells.entries) entry.key: entry.value.value,
        EshopColumnIds.PRODUCT_TITLE: 'Updated admission',
      }, commands: _Commands((_) {}), guard: ExceptionHandler.guardVoid).product;
      expect(edited.purchasedCount, 3);
      expect(edited.orderedCount, 4);
      expect(edited.paidCount, 2);
      expect(edited.sentCount, 1);
      expect(edited.copyWith(title: 'Another title').purchasedCount, 3);
      return const SizedBox.shrink();
    })));
  });
  for (final action in ['cancel', 'save', 'rejected save']) {
    testWidgets('product grid retains one draft through $action',
        (tester) async {
      var persisted = ProductModel(
          id: 7,
          title: 'Lunch',
          price: 120,
          currencyCode: 'CZK',
          data: {
            'unknown': {'retained': false}
          },
          includedInventories: [
            ProductInventoryContextModel(
                productId: 7, inventoryContextId: 9, quantity: 2)
          ]);
      final commands = _Commands((payload) {
        persisted = ProductModel.fromJson(payload);
      });
      commands.reject = action == 'rejected save';
      late SingleDataGridController<ProductGridRecord> controller;
      await tester.pumpWidget(
          MaterialApp(builder: DependencyMaterialBridge.builder, home: Scaffold(body: Builder(builder: (context) {
        ProductGridRecord record(ProductModel product) => ProductGridRecord(
            product: product,
            commands: commands,
            guard: ExceptionHandler.guardVoid);
        controller = SingleDataGridController<ProductGridRecord>(
          context: context,
          loadData: () async => [record(persisted)],
          fromPlutoJson: (json) => ProductGridRecord.fromPlutoJson(json,
              commands: commands, guard: ExceptionHandler.guardVoid),
          idColumn: EshopColumnIds.PRODUCT_ID,
          firstColumnType: DataGridFirstColumn.delete,
          actionsExtended:
              DataGridActionsController(isAddActionPossible: () => false),
          columns: [
            for (final key in record(persisted).toTrinaRow(context).cells.keys)
              TrinaColumn(
                  title: key,
                  field: key,
                  type: TrinaColumnType.text(),
                  hide: key != EshopColumnIds.PRODUCT_TITLE &&
                      key != EshopColumnIds.PRODUCT_PRICE)
          ],
        );
        return SingleTableDataGrid<ProductGridRecord>(controller);
      }))));
      await tester.pumpAndSettle();
      final row = controller.stateManager.rows.single;
      controller.stateManager.changeCellValue(
          row.cells[EshopColumnIds.PRODUCT_TITLE]!, 'Updated lunch');
      await tester.pumpAndSettle();
      expect(controller.hasPendingChanges, isTrue);
      expect(persisted.title, 'Lunch');
      if (action == 'cancel') {
        await tester.tap(find.widgetWithText(
            ElevatedButton, DataGridStrings.discardChanges));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.ok));
        await tester.pumpAndSettle();
        expect(commands.saved, isEmpty);
        expect(controller.hasPendingChanges, isFalse);
        expect(
            controller.stateManager.rows.single
                .cells[EshopColumnIds.PRODUCT_TITLE]!.value,
            'Lunch');
      } else {
        await tester.tap(
            find.widgetWithText(ElevatedButton, CommonStrings.saveChanges));
        await tester.pumpAndSettle();
        expect(commands.saved.single['id'], 7);
        expect(commands.saved.single['currency_code'], 'CZK');
        expect(commands.saved.single['data'], {
          'unknown': {'retained': false}
        });
        if (commands.reject) {
          expect(controller.hasPendingChanges, isTrue);
          expect(persisted.title, 'Lunch');
          expect(
              row.cells[EshopColumnIds.PRODUCT_TITLE]!.value, 'Updated lunch');
          expect(commands.inclusions, isEmpty);
        } else {
          expect(persisted.title, 'Updated lunch');
          expect(controller.hasPendingChanges, isFalse);
          expect(commands.inclusions, isEmpty);
          expect(commands.saved.single['inventory_contexts'], [
            {'inventory_context_id': 9, 'quantity': 2}
          ]);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

class _Commands implements EshopCommands {
  _Commands(this.persist);
  final void Function(Map<String, dynamic>) persist;
  final saved = <Map<String, dynamic>>[];
  final inclusions = <List<Map<String, dynamic>>>[];
  bool reject = false;
  @override
  Future<SavedProduct> saveProduct(Map<String, dynamic> product) async {
    saved.add(product);
    if (reject) throw StateError('Save rejected');
    persist(product);
    return SavedProduct(product['id'] as int,
        (product['expected_aggregate_version'] as int) + 1);
  }

  @override
  Future<void> updateProductInventoryContexts(
      int id, List<Map<String, dynamic>> contexts,
      {required int expectedVersion}) async {
    expect(id, 7);
    inclusions.add(contexts);
  }

  @override
  Future<void> deleteProduct(int id, {required int expectedVersion}) async =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> updateTicketProducts(
          int id, List<Map<String, dynamic>> products) async =>
      throw UnimplementedError();
}
