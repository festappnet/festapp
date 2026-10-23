import 'package:flutter/material.dart';
import '../models/inventory_context_stock.dart';
import 'package:fstapp/styles/styles_config.dart';

import 'inventory_strings.dart';
import '../models/inventory_pool_model.dart';

class InventoryPoolCard extends StatelessWidget {
  final InventoryPoolModel pool;
  final List<InventoryContextStock> contexts;
  final VoidCallback onTap;

  const InventoryPoolCard({
    super.key,
    required this.pool,
    required this.contexts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final cardColor = isDarkMode ? Colors.grey[850] : Colors.white;
    final borderColor = isDarkMode ? Colors.grey[700]! : theme.dividerColor;
    final hasContexts = contexts.isNotEmpty;

    final capacityPerContext = pool.resourceCapacity ?? 0;

    final bool useCompressedStyle = contexts.length > 5;

    const int maxItems = 12; // Show a max of 11 items + "more" indicator
    final bool isOverflowing = contexts.length > maxItems;
    final itemsToShow =
        isOverflowing ? contexts.take(maxItems - 1).toList() : contexts;

    return Card(
      elevation: 0,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      pool.title ?? InventoryStrings.cardUnnamedPool,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatItem(context,
                      icon: Icons.inventory_2_outlined,
                      label: InventoryStrings.cardStatSellable,
                      value: pool.sellableCapacity?.toString() ??
                          InventoryStrings.cardStatDynamic),
                  if (hasContexts && capacityPerContext > 0) ...[
                    const SizedBox(width: 12),
                    _buildStatItem(context,
                        icon: Icons.groups_outlined,
                        label: InventoryStrings.cardStatSlotSize,
                        value: capacityPerContext.toString()),
                  ]
                ],
              ),
              if (hasContexts) ...[
                const Divider(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const itemsPerRow = 5;
                    final spacing = useCompressedStyle ? 6.0 : 8.0;
                    final totalSpacing = spacing * (itemsPerRow - 1);
                    final chipWidth =
                        (constraints.maxWidth - totalSpacing) / itemsPerRow;

                    List<Widget> contextWidgets = itemsToShow
                        .map((c) => _ContextChip(
                              stock: c,
                              useCompressedStyle: useCompressedStyle,
                              width: chipWidth,
                            ))
                        .toList();

                    if (isOverflowing) {
                      contextWidgets.add(_buildEllipsisIndicator(context,
                          useCompressedStyle: useCompressedStyle,
                          width: chipWidth));
                    }

                    return Wrap(
                      spacing: spacing,
                      runSpacing: useCompressedStyle ? 6.0 : 12.0,
                      children: contextWidgets,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context,
      {required IconData icon, required String label, required String value}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 16, color: theme.colorScheme.onSurface.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(
          "$label: ",
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
        ),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildEllipsisIndicator(BuildContext context,
      {required bool useCompressedStyle, required double width}) {
    final theme = Theme.of(context);
    final double height = useCompressedStyle ? 40 : 56;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.more_horiz_rounded,
          size: 24, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _ContextChip extends StatelessWidget {
  final InventoryContextStock stock;
  final bool useCompressedStyle;
  final double width;

  const _ContextChip({
    required this.stock,
    required this.useCompressedStyle,
    required this.width,
  });

  // --- NEW: Helper widget for the unassigned indicator badge ---
  Widget _buildUnassignedIndicator(
      BuildContext context, int count, String contextTitle) {
    final theme = Theme.of(context);
    return Tooltip(
      // Using a new, more specific string from InventoryStrings
      message: InventoryStrings.cardTooltipUnassigned(count),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          shape: BoxShape.circle,
          border: Border.all(
              color: theme.colorScheme.onErrorContainer.withOpacity(0.5),
              width: 1),
        ),
        constraints: const BoxConstraints(
          minWidth: 20,
          minHeight: 20,
        ),
        child: Center(
          child: Text(
            count.toString(),
            style: TextStyle(
              color: theme.colorScheme.onErrorContainer,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final contextModel = stock.context;
    final orderedCapacity = stock.allocatedCount;
    final unassignedInContext = stock.unassignedCount;
    final totalCapacity = stock.physicalCount;

    final double fillPercentage =
        totalCapacity > 0 ? orderedCapacity / totalCapacity : 0.0;
    final contextTitle = contextModel.getContextTitle(context);
    final double height = useCompressedStyle ? 42 : 56;

    final TextStyle titleStyle = useCompressedStyle
        ? theme.textTheme.bodySmall!.copyWith(
            fontWeight: FontWeight.bold,
            color: isDarkMode
                ? Colors.white70
                : theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.labelMedium!.copyWith(
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white70 : theme.colorScheme.onSurface,
          );

    final TextStyle detailStyle = useCompressedStyle
        ? theme.textTheme.bodySmall!.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: isDarkMode
                ? Colors.white60
                : theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodySmall!.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: isDarkMode
                ? Colors.white60
                : theme.colorScheme.onSurfaceVariant,
          );

    final Color chipBackgroundColor = isDarkMode
        ? Colors.grey[800]!
        : theme.colorScheme.onSurface.withOpacity(0.08);

    final Color progressTrackColor = isDarkMode
        ? Colors.black.withOpacity(0.2)
        : theme.colorScheme.surfaceContainer;

    // --- MODIFIED: Wrap in a Stack to position the indicator ---
    return Stack(
      clipBehavior: Clip.none, // Allow the badge to overflow slightly if needed
      children: [
        Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: chipBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(contextTitle,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fillPercentage,
                  minHeight: useCompressedStyle ? 4 : 5,
                  color: theme.colorScheme.primary,
                  backgroundColor: progressTrackColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$orderedCapacity / $totalCapacity',
                style: detailStyle,
              ),
            ],
          ),
        ),
        if (unassignedInContext > 0)
          Positioned(
            top: -5,
            right: -5,
            child: _buildUnassignedIndicator(
                context, unassignedInContext, contextTitle),
          ),
      ],
    );
  }
}
