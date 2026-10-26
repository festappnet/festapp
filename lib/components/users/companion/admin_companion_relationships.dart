import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';

void annotateAdminCompanionRelationships(List<OccasionUserModel> users) {
  final usersById = {
    for (final user in users)
      if (user.user case final id?) id: user,
  };
  for (final user in users) {
    user.managedCompanionNames = [];
  }
  for (final companion in users) {
    final owner = usersById[companion.companionOwnerId];
    if (owner == null) continue;
    final name = [
      companion.data?[Tb.occasion_users.data_name],
      companion.data?[Tb.occasion_users.data_surname],
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
    if (name.isNotEmpty) owner.managedCompanionNames.add(name);
  }
  for (final user in users) {
    user.managedCompanionNames.sort();
  }
}
