import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/styles/styles_config.dart';

/// Info banner shown to a participant whose reporting has been blocked: they can
/// still see the page (colours) but the report action is disabled.
class CleaningBlockedBanner extends StatelessWidget {
  const CleaningBlockedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(StylesConfig.eventItemRoundness),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(Icons.block, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              CleaningStrings.blockedMessage,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
