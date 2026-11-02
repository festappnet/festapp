import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../widgets/info_tooltip_button.dart';
import 'email_delivery_indicator.dart';
import 'email_delivery_strings.dart';

/// Uses the same status indicators as the order grid, without example actions.
class EmailDeliveryStatusHelp extends StatelessWidget {
  const EmailDeliveryStatusHelp({
    super.key,
    required this.label,
    required this.message,
    required this.note,
  });

  final String label, message, note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TooltipTheme(
      data: TooltipTheme.of(context).copyWith(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: theme.textTheme.bodySmall?.copyWith(color: colors.onSurface),
      ),
      child: InfoTooltipButton(
        semanticLabel: label,
        message: message,
        richMessage: TextSpan(
          children: [
            WidgetSpan(
              child: SizedBox(
                width: math.min(
                  312,
                  math.max(0, MediaQuery.sizeOf(context).width - 64),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .7,
                  ),
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.onSurface,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final state in [
                            'pending',
                            'accepted',
                            'delivery',
                            'open',
                            'unknown',
                            'dead',
                          ])
                            Row(
                              children: [
                                IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: EmailDeliveryIndicator(
                                      summary: {'state': state},
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    state == 'open'
                                        ? '${EmailDeliveryStrings.state('open')} / ${EmailDeliveryStrings.state('click')}'
                                        : EmailDeliveryStrings.state(state),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(note),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
