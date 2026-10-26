import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/unit/views/unit_page_base.dart';

@RoutePage()
class UnitPage extends UnitPageBase {
  static const ROUTE = "unit";

  const UnitPage({@pathParam super.id, super.key});

  @override
  _UnitPageState createState() => _UnitPageState();
}

class _UnitPageState extends UnitPageBaseState<UnitPage> {
  // This state is intentionally empty.
  // All logic is inherited from UnitPageBaseState.
}
