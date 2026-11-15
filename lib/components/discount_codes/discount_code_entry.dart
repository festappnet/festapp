import 'package:material_ui/material_ui.dart';

import 'discount_summary.dart';

import 'discount_strings.dart';

class DiscountCodeEntry extends StatelessWidget {
  const DiscountCodeEntry({
    super.key,
    required this.controller,
    required this.busy,
    required this.onApply,
    required this.onRemove,
    this.quote,
    this.error,
    this.onChanged,
  });
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onApply, onRemove;
  final Map<String, dynamic>? quote;
  final String? error;
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(DiscountStrings.text('prompt')),
    children: [
      TextField(
        onChanged: (_) => onChanged?.call(),
        controller: controller,
        maxLength: 32,
        enabled: !busy,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: DiscountStrings.text('code')),
      ),
      Wrap(
        spacing: 12,
        children: [
          TextButton(
            onPressed: busy ? null : onApply,
            child: Text(DiscountStrings.text(busy ? 'busy' : 'apply')),
          ),
          TextButton(
            onPressed: busy ? null : onRemove,
            child: Text(DiscountStrings.text('remove')),
          ),
        ],
      ),
      if (error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (quote != null)
        Semantics(liveRegion: true, child: DiscountSummary(discount: quote!)),
    ],
  );
}
