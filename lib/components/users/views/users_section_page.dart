import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/users/views/users_tab.dart';

@RoutePage()
class UsersSectionPage extends StatelessWidget {
  const UsersSectionPage({super.key});
  @override
  Widget build(BuildContext context) => UsersTab();
}
