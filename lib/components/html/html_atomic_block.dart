import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import 'html_strings.dart';

Future<void> showHtmlAtomicBlockInfo(
  BuildContext context, {
  required String label,
  required String description,
}) => showDialog<void>(
  context: context,
  builder: (context) => AppAlertDialog(
    title: Text(label),
    content: Text(description),
    onClose: () => Navigator.pop(context),
  ),
);

/// Shared interaction shell for HTML slots and block template variables.
/// Serialized identity, document transactions and movement bounds stay outside.
class HtmlAtomicBlock extends StatefulWidget {
  const HtmlAtomicBlock({
    super.key,
    required this.label,
    this.description = '',
    required this.child,
    this.selected = false,
    this.onSelect,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });
  final String label;
  final String description;
  final Widget child;
  final bool selected;
  final VoidCallback? onSelect, onDelete, onMoveUp, onMoveDown;
  @override
  State<HtmlAtomicBlock> createState() => _HtmlAtomicBlockState();
}

class _HtmlAtomicBlockState extends State<HtmlAtomicBlock> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = hovered || focused || widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Focus(
        onFocusChange: (value) => setState(() => focused = value),
        child: Semantics(
          label: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onSelect,
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: widget.child,
                ),
                if (active)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: focused || widget.selected
                                ? colors.primary
                                : colors.primary.withValues(alpha: .7),
                            width: focused || widget.selected ? 2 : 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Material(
                    color: colors.surfaceContainerHigh,
                    elevation: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: widget.label,
                          icon: const Icon(Icons.info_outline, size: 18),
                          onPressed: () => showHtmlAtomicBlockInfo(
                            context,
                            label: widget.label,
                            description: widget.description,
                          ),
                        ),
                        if (active && widget.onDelete != null) ...[
                          IconButton(
                            tooltip: HtmlStrings.moveUp,
                            onPressed: widget.onMoveUp,
                            icon: const Icon(Icons.arrow_upward, size: 18),
                          ),
                          IconButton(
                            tooltip: HtmlStrings.moveDown,
                            onPressed: widget.onMoveDown,
                            icon: const Icon(Icons.arrow_downward, size: 18),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .deleteButtonTooltip,
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
