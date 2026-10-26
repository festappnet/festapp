import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/unit/views/unit_page_base.dart';

@RoutePage()
class OrganizationPage extends UnitPageBase {
  static const ROUTE = "organization";

  const OrganizationPage({@pathParam super.id, super.key});

  @override
  _OrganizationPageState createState() => _OrganizationPageState();
}

class _OrganizationPageState extends UnitPageBaseState<OrganizationPage> {
  // This state is intentionally empty.
  // All logic is inherited from UnitPageBaseState.
}
