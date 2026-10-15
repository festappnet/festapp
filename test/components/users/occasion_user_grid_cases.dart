import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  testWidgets('admin grid preserves profile version and accommodation',
      (tester) async {
    const expectedAggregateVersion = 7;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const SizedBox();
      }),
    ));

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
