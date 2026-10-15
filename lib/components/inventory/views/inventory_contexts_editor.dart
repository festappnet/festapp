import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/theme_config.dart';
import 'inventory_strings.dart';

class InventoryContextsEditor extends StatelessWidget {
  final List<InventoryContextModel> activeContexts;
  final List<InventoryContextModel> deletedContexts;
  final List<InventoryContextModel> originalContexts;
  final InventoryPoolModel? pool;
  final List<ProductModel> allProducts;
  final Function(int, int) onReorder;
  final Function(InventoryContextModel) onEdit;
  final Function(InventoryContextModel) onRemove;
  final Function(InventoryContextModel) onRestore;
  final Function(InventoryContextModel, List<ProductModel>) onEditProduct;

  const InventoryContextsEditor({
    super.key,
    required this.activeContexts,
    required this.deletedContexts,
    required this.originalContexts,
    required this.pool,
    required this.allProducts,
    required this.onReorder,
    required this.onEdit,
    required this.onRemove,
    required this.onRestore,
    required this.onEditProduct,
  });

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverReorderableList(
          itemBuilder: (context, index) {
            return _buildContextEditor(context, activeContexts[index], index,
                isDeleted: false);
          },
          itemCount: activeContexts.length,
          onReorder: onReorder,
        ),
        if (deletedContexts.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(InventoryStrings.settingsMarkedForDeletion,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final deletedItem in deletedContexts)
                      _buildContextEditor(context, deletedItem, -1,
                          isDeleted: true)
                  ],
                )
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildContextEditor(
      BuildContext context, InventoryContextModel contextModel, int index,
      {required bool isDeleted}) {
    contextModel.inventoryPool = pool;

    final isNew = originalContexts.firstWhereOrNull((c) =>
            (c.id != null && c.id == contextModel.id) ||
            (c.id == null && c == contextModel)) ==
        null;

    final subtitleStyle = TextStyle(
      decoration: isDeleted ? TextDecoration.lineThrough : null,
      color: isDeleted
          ? Theme.of(context).disabledColor.withOpacity(0.7)
          : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
    );

    return Card(
      key: ValueKey(contextModel.id ?? contextModel.hashCode),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      color: isDeleted
          ? Colors.red.withOpacity(0.05)
          : isNew
              ? Colors.green.withOpacity(0.05)
              : null,
      child: Row(
        children: <Widget>[
          ReorderableDragStartListener(
            index: index,
            enabled: !isDeleted,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.transparent,
              child: Center(
                child: isDeleted
                    ? const SizedBox(width: 12)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          4,
                          (_) => Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              2,
                              (_) => Container(
                                width: 3.5,
                                height: 3.5,
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).disabledColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListTile(
              contentPadding: const EdgeInsets.only(right: 16, left: 0),
              title: Text(
                contextModel.getContextTitle(context),
                style: TextStyle(
                  decoration: isDeleted ? TextDecoration.lineThrough : null,
                  color: isDeleted ? Theme.of(context).disabledColor : null,
                ),
              ),
              // MODIFICATION: Subtitle now uses the new title (price) format.
              subtitle: contextModel.product == null
                  ? null
                  : Text(
                      contextModel.product!.getFormattedProductTitle(),
                      style: subtitleStyle,
                    ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.category_rounded),
            tooltip: InventoryStrings.settingsProductTooltip,
            onPressed: isDeleted
                ? null
                : () {
                    final assignableProducts = allProducts
                        .where((p) => p.includedInventories.any(
                            (ic) => ic.inventoryContextId == contextModel.id))
                        .toList();
                    onEditProduct(contextModel, assignableProducts);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: InventoryStrings.edit,
            onPressed: isDeleted ? null : () => onEdit(contextModel),
          ),
          IconButton(
            icon: isDeleted
                ? const Icon(Icons.add_circle_outline, color: Colors.green)
                : Icon(Icons.delete_outline,
                    color: ThemeConfig.redColor(context)),
            tooltip:
                isDeleted ? InventoryStrings.restore : InventoryStrings.remove,
            onPressed: () {
              if (isDeleted) {
                onRestore(contextModel);
              } else {
                onRemove(contextModel);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
