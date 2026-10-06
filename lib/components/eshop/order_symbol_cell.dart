import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'orders_strings.dart';

/// Readonly symbol with an explicit copy action, shared by the order grids.
class OrderSymbolCell extends StatelessWidget {
  final String symbol;
  final TextStyle? style;
  const OrderSymbolCell({super.key, required this.symbol, this.style});

  @override
  Widget build(BuildContext context) {
    if (symbol.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<void>(
      tooltip: symbol,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          enabled: false,
          child: _SymbolCopyAction(symbol: symbol),
        ),
      ],
      child: Align(alignment: AlignmentDirectional.centerStart,
          child: Text(symbol, style: style, maxLines: 1)),
    );
  }
}

class _SymbolCopyAction extends StatefulWidget {
  final String symbol;
  const _SymbolCopyAction({required this.symbol});

  @override
  State<_SymbolCopyAction> createState() => _SymbolCopyActionState();
}

class _SymbolCopyActionState extends State<_SymbolCopyAction> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(widget.symbol, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(width: 8),
      IconButton(
        tooltip: _copied ? CommonStrings.copiedToClipboard : OrdersStrings.copy,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: Icon(_copied ? Icons.check : Icons.copy,
            color: _copied ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: widget.symbol));
          if (mounted) setState(() => _copied = true);
        },
      ),
    ],
  );
}
