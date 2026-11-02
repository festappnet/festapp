import 'package:material_ui/material_ui.dart';

import '../_shared/copy_button.dart';

/// Readonly symbol and compact inline copy action, shared by order grids.
class OrderSymbolCell extends StatelessWidget {
  final String symbol;
  final TextStyle? style;
  final VoidCallback? onOpen;
  const OrderSymbolCell({
    super.key,
    required this.symbol,
    this.style,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (symbol.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: symbol,
            child: onOpen == null
                ? Text(symbol, style: style, maxLines: 1)
                : TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            symbol,
                            style: style?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new, size: 14),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 2),
        CopyButton(value: symbol),
      ],
    );
  }
}
