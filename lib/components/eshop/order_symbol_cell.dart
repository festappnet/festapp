import 'package:flutter/material.dart';
import '../_shared/copy_button.dart';

/// Readonly symbol and compact inline copy action, shared by order grids.
class OrderSymbolCell extends StatelessWidget {
  final String symbol;
  final TextStyle? style;
  const OrderSymbolCell({super.key, required this.symbol, this.style});

  @override
  Widget build(BuildContext context) {
    if (symbol.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      Expanded(child: Tooltip(message: symbol,
          child: Text(symbol, style: style, maxLines: 1))),
      const SizedBox(width: 2),
      CopyButton(value: symbol),
    ]);
  }
}
