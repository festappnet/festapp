import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/schedule/exclusive_group_model.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  testWidgets('remaining versioned admin grids preserve optimistic versions',
      (tester) async {
    const expectedAggregateVersion = 13;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const SizedBox();
      }),
    ));

    final information = InformationModel.fromJson({
      Tb.information.id: 1,
      Tb.information.title: 'Info',
      Tb.information.type: InformationModel.songType,
      TrinaRowVersion.column: expectedAggregateVersion,
    });
    final exclusiveGroup = ExclusiveGroupModel.fromJson({
      Tb.exclusive_groups.id: 2,
      Tb.exclusive_groups.title: 'Exclusive',
      Tb.exclusive_events.table: <dynamic>[],
      TrinaRowVersion.column: expectedAggregateVersion,
    });
    final userGroup = UserGroupInfoModel.fromJson({
      Tb.user_group_info.id: 3,
      Tb.user_group_info.title: 'Group',
      TrinaRowVersion.column: expectedAggregateVersion,
    });
    final resource = ResourceModel.fromJson({
      Tb.resources.id: 4,
      Tb.resources.title: 'Chair',
      Tb.resources.inventory_pool: 5,
      TrinaRowVersion.column: expectedAggregateVersion,
    });

    final informationRow = information.toTrinaRow(context).toJson();
    expect(InformationModel.fromPlutoJson(informationRow).aggregateVersion,
        expectedAggregateVersion);
    expect(InformationModel.fromPlutoJsonGame(informationRow).aggregateVersion,
        expectedAggregateVersion);
    expect(
        InformationModel.fromPlutoJsonType(
                informationRow, InformationModel.songType)
            .aggregateVersion,
        expectedAggregateVersion);
    expect(
        ExclusiveGroupModel.fromPlutoJson(
                exclusiveGroup.toTrinaRow(context).toJson())
            .aggregateVersion,
        expectedAggregateVersion);
    expect(
        UserGroupInfoModel.fromGamePlutoJson(
                userGroup.toTrinaRow(context).toJson())
            .aggregateVersion,
        expectedAggregateVersion);
    expect(
        ResourceModel.fromPlutoJson(resource.toTrinaRow(context).toJson())
            .aggregateVersion,
        expectedAggregateVersion);
  });
}
