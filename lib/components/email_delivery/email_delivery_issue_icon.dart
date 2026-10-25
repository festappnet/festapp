import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart';

/// Same white-on-red treatment as other actionable order problems.
class EmailDeliveryIssueIcon extends StatelessWidget {
  const EmailDeliveryIssueIcon({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Badge(
        isLabelVisible: count > 1,
        label: Text('$count'),
        child: CircleAvatar(
          radius: 10,
          backgroundColor: ThemeConfig.redColor(context),
          child: const Icon(Icons.mark_email_unread_outlined,
              size: 14, color: Colors.white),
        ),
      );
}
