import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/client_changes/client_changes_tab.dart';

@RoutePage()
class ChangesSectionPage extends StatelessWidget {
  const ChangesSectionPage({super.key});
  @override
  Widget build(BuildContext context) => const ClientChangesTab();
}
