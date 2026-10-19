import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';
import 'package:collection/collection.dart';

import '../../_shared/common_strings.dart';

class BlueprintGroupsPanel extends StatelessWidget {
  final BlueprintModel? blueprint;
  final BlueprintGroupModel? currentGroup;
  final ValueChanged<BlueprintGroupModel?> onGroupSelected;
  final VoidCallback? onAddGroup;
  final VoidCallback? onDeleteGroup;
  final ValueChanged<BlueprintGroupModel>? onEditGroupProduct;
  final bool canEdit;

  const BlueprintGroupsPanel({
    super.key,
    required this.blueprint,
    required this.currentGroup,
    required this.onGroupSelected,
    this.onAddGroup,
    this.onDeleteGroup,
    this.onEditGroupProduct,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (blueprint == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Ensure groups are sorted
    blueprint!.groups!
        .sort((a, b) => Utilities.naturalCompare(a.title!, b.title!));

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                BlueprintStrings.groupsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: CommonStrings.addNew,
                  onPressed: canEdit ? onAddGroup : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: CommonStrings.delete,
                  onPressed: canEdit ? onDeleteGroup : null,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: blueprint!.groups!.length,
            itemBuilder: (context, index) {
              final group = blueprint!.groups![index];
              final isSelected = currentGroup == group;
              return GestureDetector(
                onTap: () {
                  if (isSelected) {
                    onGroupSelected(null);
                  } else {
                    onGroupSelected(group);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                    fontWeight:
                                        isSelected ? FontWeight.bold : null,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            // Show product info (Mixed or Specific)
                            Builder(builder: (context) {
                              // Logic to determine Mixed vs Uniform
                              bool isMixed = false;
                              // Default logic: group.product ?? implicit first child ?? blueprint default
                              // But we need to check consistency across all children.

                              final objects = group.objects;
                              final fallbackProduct = group.product ??
                                  blueprint!.spotProducts.firstOrNull;

                              // The product we will display if uniform
                              final displayProduct = objects.isNotEmpty
                                  ? (objects.first.product ?? group.product)
                                  : fallbackProduct;

                              if (objects.isNotEmpty) {
                                final firstId = displayProduct?.id;
                                for (var obj in objects) {
                                  final p = obj.product ?? group.product;
                                  if (p?.id != firstId) {
                                    isMixed = true;
                                    break;
                                  }
                                }
                              }

                              // 1. Mixed State
                              if (isMixed) {
                                return Text(
                                  BlueprintStrings.mixedProducts,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.9)
                                            : Colors
                                                .orange, // Orange to hint at complexity
                                        fontStyle: FontStyle.italic,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                );
                              }

                              // 2. Uniform State
                              final priceString = displayProduct != null
                                  ? Utilities.formatPrice(
                                      context, displayProduct.price ?? 0)
                                  : null;
                              final productTitle = displayProduct?.title ??
                                  BlueprintStrings.noProductAssigned;

                              return Text(
                                priceString != null
                                    ? "$productTitle ($priceString)"
                                    : productTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.9)
                                          : ThemeConfig.grey600(context),
                                    ),
                                overflow: TextOverflow.ellipsis,
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Group for count and buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "(${group.objects.length})",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (canEdit)
                            IconButton(
                              icon: const Icon(Icons.category_outlined),
                              iconSize: 20,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              tooltip: BlueprintStrings.manageGroupProducts,
                              onPressed: () => onEditGroupProduct?.call(group),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
