import 'package:flutter/material.dart';
import '../../templates/layout_templates.dart';
import 'layout_strings.dart';

/// Compact gallery choice with details available on hover and keyboard focus.
class LayoutTemplateCard extends StatefulWidget {
  const LayoutTemplateCard({
    super.key,
    required this.template,
    required this.preview,
    required this.onPressed,
  });
  final LayoutTemplate template;
  final Widget preview;
  final VoidCallback onPressed;

  @override
  State<LayoutTemplateCard> createState() => _LayoutTemplateCardState();
}

class _LayoutTemplateCardState extends State<LayoutTemplateCard> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    return Tooltip(
      key: _tooltip,
      message: VenueLayoutStrings.text(context, template.description),
      child: OutlinedButton(
        onFocusChange: (focused) {
          if (focused) {
            _tooltip.currentState?.ensureTooltipVisible();
          } else {
            Tooltip.dismissAllToolTips();
          }
        },
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(12),
          alignment: Alignment.topLeft,
        ),
        onPressed: widget.onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: IgnorePointer(child: widget.preview),
              ),
            ),
            const SizedBox(height: 8),
            LayoutText(
              template.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Semantics(
              label: VenueLayoutStrings.text(
                context,
                '${template.seatCount} seats · ${template.standingCapacity} standing',
              ),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const Icon(Icons.event_seat_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text('${template.seatCount}'),
                    if (template.standingCapacity > 0) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.accessibility_new, size: 16),
                      const SizedBox(width: 4),
                      Text('${template.standingCapacity}'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
