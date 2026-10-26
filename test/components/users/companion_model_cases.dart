import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';

void main() {
  test('companion DTO preserves identity, group, origin and deletion policy',
      () {
    final model = CompanionModel.fromJson({
      'id': 'participant',
      'name': 'Ada',
      'surname': 'Lovelace',
      'group_title': 'DISK 19, DISK 44',
      'services': {
        'accommodation': {'room-a': 'paid'},
      },
      'origin': 'admin_assigned',
      'can_owner_delete': false,
      'event_ids': [1, 2],
    });
    expect(model.fullName, 'Ada Lovelace');
    expect(model.groupTitle, 'DISK 19, DISK 44');
    expect(model.occasionServices['accommodation'], {'room-a': 'paid'});
    expect(model.canOwnerDelete, isFalse);
    final roundTrip = CompanionModel.fromJson(model.toJson());
    expect(roundTrip.origin, 'admin_assigned');
    expect(roundTrip.occasionServices['accommodation'], {'room-a': 'paid'});
  });
}
