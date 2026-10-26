import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/theme_config.dart';

class CustomThreeStateCheckbox extends StatelessWidget {
  final String currentState;
  final void Function(String) onStateChanged;
  final bool isEnabled;

  // Optional custom icons for each state
  final IconData? noneStateIcon;
  final IconData? paidStateIcon;
  final IconData? usedStateIcon;

  const CustomThreeStateCheckbox({
    super.key,
    required this.currentState,
    required this.onStateChanged,
    this.isEnabled = true,
    this.noneStateIcon,
    this.paidStateIcon,
    this.usedStateIcon,
  });

  // Define the next state in the cycle
  String _getNextState(String currentState) {
    switch (currentState) {
      case DbOccasions.serviceNone:
        return DbOccasions.servicePaid;
      case DbOccasions.servicePaid:
        return DbOccasions.serviceUsed;
      case DbOccasions.serviceUsed:
      default:
        return DbOccasions.serviceNone;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled
          ? () {
              String nextState = _getNextState(currentState);
              onStateChanged(nextState);
            }
          : null,
      child: Icon(
        currentState == DbOccasions.serviceNone
            ? noneStateIcon ?? Icons.check_box_outline_blank // Default icon
            : currentState == DbOccasions.servicePaid
                ? paidStateIcon ?? Icons.check_box_outlined // Default icon
                : usedStateIcon ?? Icons.check_box, // Default icon
        color: isEnabled
            ? ThemeConfig.blackColor(context)
            : Colors.grey, // Optional: Disabled color
      ),
    );
  }
}
