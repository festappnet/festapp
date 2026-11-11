import 'package:festapp_core/time.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:fstapp/components/users/unit_user_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import '../../support/fixtures/rights_context_fixture.dart';

import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  setUpAll(OccasionTimeContext.initializeTimeZones);
  for (final canEditUnit in [true, false]) {
    testWidgets('unit profile editing follows unit capability: $canEditUnit', (
      tester,
    ) async {
      final rights = RightsContextFixture(
        context: OccasionLinkModel(
          capabilities: {
            AuthorizationCapabilities.unitUsersWrite: canEditUnit,
            AuthorizationCapabilities.usersWrite: !canEditUnit,
          },
        ),
      );
      addTearDown(rights.dispose);
      final fields = [UserColumns.NAME, UserColumns.SURNAME, UserColumns.SEX];
      final columns = UserColumns.generateColumns(
        fields,
        canEditProfile: RightsService.canUpdateUnitUsers,
      );
      expect(
        columns.map((column) => column.enableEditingMode),
        everyElement(canEditUnit),
      );
      // The occasion grid must retain its independent permission boundary.
      expect(
        UserColumns.generateColumns(fields)
            .map((column) => column.enableEditingMode),
        everyElement(!canEditUnit),
      );

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final row = UnitUserModel.newRow(12).toTrinaRow(context);
      final gridRow = TrinaRow(
        cells: {for (final field in fields) field: row.cells[field]!},
      );
      late TrinaGridStateManager manager;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: TrinaGrid(
              columns: columns,
              rows: [gridRow],
              onLoaded: (event) => manager = event.stateManager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        UserColumns.NAME: 'Jana',
        UserColumns.SURNAME: 'Nováková',
      }.entries) {
        manager.setCurrentCell(gridRow.cells[entry.key], 0);
        manager.setKeepFocus(true);
        manager.setEditing(true);
        await tester.pumpAndSettle();
        expect(manager.isEditing, canEditUnit);
        if (canEditUnit) {
          await tester.enterText(find.byType(EditableText), entry.value);
          await tester.pump();
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
            entry.value,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(gridRow.cells[entry.key]!.value, entry.value);
        } else {
          expect(find.byType(EditableText), findsNothing);
        }
      }
      final user = UnitUserModel.fromPlutoJson(row.toJson());
      expect(user.name, canEditUnit ? 'Jana' : '');
      expect(user.surname, canEditUnit ? 'Nováková' : '');
    });
  }

  for (final birthday in [null, '1970-01-01']) {
    testWidgets('new-row roundtrip preserves optional birth date $birthday', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final row = OccasionUserModel.newRow(7)
        ..data = {
          Tb.occasion_users.data_email: 'grid@example.invalid',
          if (birthday != null) Tb.occasion_users.data_birthDate: birthday,
        };
      final restored = OccasionUserModel.fromPlutoJson(
        row.toTrinaRow(context).toJson(),
      );
      expect(
        restored.data?[Tb.occasion_users.data_birthDate],
        birthday == null ? isNull : startsWith('1970-01-01'),
      );
    });
  }

  testWidgets('admin grid preserves profile version and accommodation', (
    tester,
  ) async {
    const expectedAggregateVersion = 7;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    final loaded = OccasionUserModel.fromJson({
      Tb.occasion_users.user: '00000000-0000-0000-0000-000000000001',
      Tb.occasion_users.is_receptionist: true,
      Tb.occasion_users.data: <String, dynamic>{
        Tb.occasion_users.data_appLinksSent: true,
      },
      Tb.occasion_users.services: <String, dynamic>{
        DbOccasions.serviceTypeAccommodation: <String, dynamic>{
          'room-a': DbOccasions.servicePaid,
        },
      },
      OccasionUserModel.aggregateVersionColumn: expectedAggregateVersion,
    });

    final edited = OccasionUserModel.fromPlutoJson(
      loaded.toTrinaRow(context).toJson(),
    );

    expect(edited.aggregateVersion, expectedAggregateVersion);
    expect(edited.isReceptionist, isTrue);
    expect(edited.data?[Tb.occasion_users.data_appLinksSent], isTrue);
    expect(edited.services?[DbOccasions.serviceTypeAccommodation], {
      'room-a': DbOccasions.servicePaid,
    });
  });
}
