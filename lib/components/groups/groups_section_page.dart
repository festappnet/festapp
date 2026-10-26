import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/groups/user_groups_tab.dart';

@RoutePage()
class GroupsSectionPage extends StatelessWidget {
  const GroupsSectionPage({super.key});
  @override
  Widget build(BuildContext context) => UserGroupsTab();
}
