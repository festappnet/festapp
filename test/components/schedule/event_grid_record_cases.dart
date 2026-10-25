import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:festapp_core/program.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import 'package:fstapp/components/schedule/event_commands.dart';
import 'package:fstapp/components/schedule/event_grid_record.dart';
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
  for (final action in ['cancel', 'save', 'rejected save']) {
    testWidgets('event grid retains one draft through $action', (tester) async {
      var persisted = EventModel(
          id: 7,
          title: 'Lunch',
          aggregateVersion: 4,
          timeContext: OccasionTimeContext(tz.UTC),
          startTime: DateTime(2026, 8, 9, 10),
          endTime: DateTime(2026, 8, 9, 11),
          data: {
            'unknown': {'retained': false}
          },
          parentEventIds: [
            9,
            2
          ],
          eventRolesIds: [
            8
          ]);
      final commands = _Commands((event) {
        persisted = event;
      });
      commands.reject = action == 'rejected save';
      late SingleDataGridController<EventGridRecord> controller;
      await tester.pumpWidget(
          MaterialApp(builder: DependencyMaterialBridge.builder, home: Scaffold(body: Builder(builder: (context) {
        EventGridRecord record(EventModel event) =>
            EventGridRecord(event: event, commands: commands, occasionId: 1);
        controller = SingleDataGridController<EventGridRecord>(
          context: context,
          loadData: () async => [record(persisted)],
          fromPlutoJson: (json) => EventGridRecord.fromPlutoJson(json,
              commands: commands,
              occasionId: 1,
              timeContext: OccasionTimeContext(tz.UTC)),
          idColumn: EventModel.idColumn,
          firstColumnType: DataGridFirstColumn.delete,
          actionsExtended:
              DataGridActionsController(isAddActionPossible: () => false),
          columns: [
            for (final key in record(persisted).toTrinaRow(context).cells.keys)
              TrinaColumn(
                  title: key,
                  field: key,
                  type: TrinaColumnType.text(),
                  hide: key != EventModel.titleColumn &&
                      key != EventModel.startTimeColumn)
          ],
        );
        return SingleTableDataGrid<EventGridRecord>(controller);
      }))));
      await tester.pumpAndSettle();
      final row = controller.stateManager.rows.single;
      controller.stateManager
          .changeCellValue(row.cells[EventModel.titleColumn]!, 'Updated lunch');
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
            controller
                .stateManager.rows.single.cells[EventModel.titleColumn]!.value,
            'Lunch');
      } else {
        await tester.tap(
            find.widgetWithText(ElevatedButton, CommonStrings.saveChanges));
        await tester.pumpAndSettle();
        expect(commands.saved.single.id, 7);
        expect(commands.saved.single.aggregateVersion, 4);
        expect(commands.saved.single.parentEventIds, [9, 2]);
        expect(commands.saved.single.eventRolesIds, [8]);
        expect(commands.saved.single.occasionId, 1);
        expect(commands.saved.single.data, {
          'unknown': {'retained': false},
          'is_cancelled': false,
          'counseling_entry': false
        });
        if (commands.reject) {
          expect(controller.hasPendingChanges, isTrue);
          expect(persisted.title, 'Lunch');
          expect(row.cells[EventModel.titleColumn]!.value, 'Updated lunch');
        } else {
          expect(persisted.title, 'Updated lunch');
          expect(controller.hasPendingChanges, isFalse);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

class _Commands implements EventCommands {
  _Commands(this.persist);
  final void Function(EventModel) persist;
  final saved = <EventModel>[];
  bool reject = false;
  @override
  Future<EventCommandResult> save(EventModel event) async {
    saved.add(event);
    if (reject)
      return const EventCommandResult(
          status: EventCommandStatus.rejected, version: 4);
    final receipt = event.copyWith(aggregateVersion: 5);
    persist(receipt);
    return EventCommandResult(
        status: EventCommandStatus.applied, version: 5, event: receipt);
  }

  @override
  Future<EventCommandResult> delete(EventModel event) async =>
      throw UnimplementedError();
}
