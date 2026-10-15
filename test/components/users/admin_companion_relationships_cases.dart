import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/admin_companion_relationships.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  test('admin roster annotates both sides from a fixture relation', () {
    final owner = OccasionUserModel(
      user: 'owner',
      data: {
        Tb.occasion_users.data_name: 'Owner',
        Tb.occasion_users.data_surname: 'Test',
      },
    );
    final companion = OccasionUserModel(
      user: 'companion',
      companionOwnerId: 'owner',
      companionOwnerName: 'Owner Test',
      data: {
        Tb.occasion_users.data_name: 'Companion',
        Tb.occasion_users.data_surname: 'Test',
      },
    );

    annotateAdminCompanionRelationships([owner, companion]);

    expect(owner.managedCompanionNames, ['Companion Test']);
    expect(companion.companionOwnerName, 'Owner Test');
    expect(companion.managedCompanionNames, isEmpty);
  });
}
