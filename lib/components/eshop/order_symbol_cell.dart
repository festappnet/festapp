import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'orders_strings.dart';

/// Readonly symbol and compact inline copy action, shared by order grids.
class OrderSymbolCell extends StatefulWidget {
  final String symbol;
  final TextStyle? style;
  const OrderSymbolCell({super.key, required this.symbol, this.style});

  @override
  State<OrderSymbolCell> createState() => _OrderSymbolCellState();
}

class _OrderSymbolCellState extends State<OrderSymbolCell> {
  bool _copied = false;

  @override
  void didUpdateWidget(covariant OrderSymbolCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) _copied = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.symbol.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(child: Tooltip(message: widget.symbol,
          child: Text(widget.symbol, style: widget.style, maxLines: 1))),
      const SizedBox(width: 4),
      SizedBox(width: 30, height: 30, child: IconButton(
        tooltip: _copied ? CommonStrings.copiedToClipboard : OrdersStrings.copy,
        padding: const EdgeInsets.all(6),
        iconSize: 18,
        style: IconButton.styleFrom(
          foregroundColor: _copied ? colors.onPrimary : colors.onSurface,
          backgroundColor: _copied ? colors.primary : colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        icon: Icon(_copied ? Icons.check : Icons.copy),
        onPressed: () async {
          final symbol = widget.symbol;
          await Clipboard.setData(ClipboardData(text: symbol));
          if (mounted && widget.symbol == symbol) setState(() => _copied = true);
        },
      )),
    ]);
  }
}
