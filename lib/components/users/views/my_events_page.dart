import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

import 'login_page.dart';

/// A private account entry: known organizers resume administration; accounts
/// without an organizer keep an honest workspace instead of returning to public home.
@RoutePage()
class MyEventsPage extends StatelessWidget {
  static const String ROUTE = 'admin/my-events';
  const MyEventsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const LoginPage(redirect: '/admin/my-events', showMyEventsWhenEmpty: true);
}
