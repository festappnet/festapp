import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/dialog_helper.dart';

import 'data_grid_strings.dart';
import 'pluto_abstract.dart';

/// The same model labels and optional parent grouping for every grid action.
class DataGridActionConfirmation {
  static Future<bool> show<T extends ITrinaRowModel>({
    required BuildContext context,
    required String title,
    required List<T> items,
    String? message,
    String? itemsLabel,
    String? confirmButtonText,
    String? cancelButtonText,
    ITrinaRowModel? Function(T)? groupBy,
  }) {
    if (items.isEmpty) return Future.value(false);
    return DialogHelper.showConfirmationDialogRich(
      context: context,
      title: title,
      confirmButtonText: confirmButtonText,
      cancelButtonText: cancelButtonText,
      content: DataGridActionSummary<T>(
        items: items,
        message: message,
        itemsLabel: itemsLabel,
        groupBy: groupBy,
      ),
    );
  }
}

class DataGridActionSummary<T extends ITrinaRowModel> extends StatelessWidget {
  final List<T> items;
  final String? message;
  final String? itemsLabel;
  final ITrinaRowModel? Function(T)? groupBy;

  const DataGridActionSummary({
    super.key,
    required this.items,
    this.message,
    this.itemsLabel,
    this.groupBy,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <Object, (ITrinaRowModel?, List<T>)>{};
    for (final item in items) {
      final parent = groupBy?.call(item);
      final key = parent == null
          ? null
          : (parent.runtimeType, parent.id ?? parent);
      // Ungrouped items share one flat list.
      final group = groups.putIfAbsent(key ?? 'ungrouped', () => (parent, []));
      group.$2.add(item);
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) ...[Text(message!), const SizedBox(height: 16)],
          Text('${itemsLabel ?? DataGridStrings.items}: ${items.length}'),
          for (final group in groups.values) ...[
            const SizedBox(height: 12),
            if (group.$1 != null) ...[
              SelectableText(
                group.$1!.toBasicString(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${itemsLabel ?? DataGridStrings.items}: ${group.$2.length}',
              ),
              const SizedBox(height: 8),
            ],
            for (final item in group.$2)
              Padding(
                padding: EdgeInsets.only(
                  left: group.$1 == null ? 0 : 16,
                  bottom: 8,
                ),
                child: SelectableText(item.toBasicString()),
              ),
          ],
        ],
      ),
    );
  }
}
