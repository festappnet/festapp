import 'dart:async';
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
  Timer? _feedbackTimer;

  @override
  void didUpdateWidget(covariant OrderSymbolCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _feedbackTimer?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.symbol.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(child: Tooltip(message: widget.symbol,
          child: Text(widget.symbol, style: widget.style, maxLines: 1))),
      const SizedBox(width: 2),
      SizedBox(width: 24, height: 30, child: IconButton(
        tooltip: _copied ? CommonStrings.copiedToClipboard : OrdersStrings.copy,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        iconSize: 16,
        style: IconButton.styleFrom(
          foregroundColor: _copied
              ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.greenAccent.shade400 : Colors.green.shade700)
              : colors.onSurfaceVariant,
          backgroundColor: Colors.transparent,
        ),
        icon: Icon(_copied ? Icons.check : Icons.copy),
        onPressed: () async {
          final symbol = widget.symbol;
          await Clipboard.setData(ClipboardData(text: symbol));
          if (mounted && widget.symbol == symbol) {
            _feedbackTimer?.cancel();
            setState(() => _copied = true);
            _feedbackTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _copied = false);
            });
          }
        },
      )),
    ]);
  }
}
