import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/product_inventory_context_model.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class InventoryInclusionRenderer extends StatefulWidget {
  final TrinaColumnRendererContext rendererContext;
  final ProductModel product;
  final List<InventoryContextModel> availableContexts;

  const InventoryInclusionRenderer({
    super.key,
    required this.rendererContext,
    required this.product,
    required this.availableContexts,
  });

  @override
  State<InventoryInclusionRenderer> createState() =>
      _InventoryInclusionRendererState();
}

class _InventoryInclusionRendererState
    extends State<InventoryInclusionRenderer> {
  // Store the initial state of inclusions as a string when the dialog opens
  String? _initialInclusionsString;

  void _triggerGridUpdate() {
    var newValue =
        ProductModel.getInventoryDisplayValue(widget.product, context);
    // Only trigger a change if the new value is different from the initial value
    if (newValue != _initialInclusionsString) {
      widget.rendererContext.stateManager.changeCellValue(
        widget.rendererContext.cell,
        newValue,
        force: true, // Use force: true to ensure the change is registered
      );
    }
    // Reset initial string after update attempt
    _initialInclusionsString = null;
  }

  Future<void> _showInventoryDialog(BuildContext context) async {
    // Capture the current state as a string before the dialog opens
    _initialInclusionsString =
        ProductModel.getInventoryDisplayValue(widget.product, context);

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          // MODIFIED LINE: Added the product title to the dialog title
          title: Text(InventoryStrings.inclusionManageTitle(
              widget.product.title ?? "")),
          content: SizedBox(
            // Set max width for the dialog content
            width: StylesConfig.formMaxWidthMid,
            // The dialog content is now its own StatefulWidget
            child: _InventoryDialogContent(
              product: widget.product,
              availableContexts: widget.availableContexts,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(CommonStrings.close),
            ),
          ],
        );
      },
    );

    // After the dialog is closed, trigger a single update to the grid.
    _triggerGridUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _showInventoryDialog(context),
          tooltip: InventoryStrings.inclusionManageTooltip,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: widget.product.includedInventories.map((link) {
                final quantityText =
                    link.quantity > 1 ? " (x${link.quantity})" : "";
                final labelText =
                    "${link.inventoryContext?.getFullTitle(context) ?? '...'}$quantityText";

                return Chip(
                  label: Text(labelText),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(4),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// New StatefulWidget to manage the dialog's internal state
class _InventoryDialogContent extends StatefulWidget {
  final ProductModel product;
  final List<InventoryContextModel> availableContexts;

  const _InventoryDialogContent({
    required this.product,
    required this.availableContexts,
  });

  @override
  State<_InventoryDialogContent> createState() =>
      _InventoryDialogContentState();
}

class _InventoryDialogContentState extends State<_InventoryDialogContent> {
  final TextEditingController _searchController = TextEditingController();
  List<InventoryContextModel> _filteredAvailableContexts = [];

  @override
  void initState() {
    super.initState();
    // Initialize filtered list with all available contexts
    _filteredAvailableContexts = List.from(widget.availableContexts);
    // Add listener for search input changes
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterContexts(_searchController.text);
  }

  void _filterContexts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredAvailableContexts = List.from(widget.availableContexts);
      });
      return;
    }

    final normalizedQuery = Utilities.removeDiacritics(query).toLowerCase();

    setState(() {
      _filteredAvailableContexts =
          widget.availableContexts.where((contextModel) {
        // Use the BuildContext from this dialog's state
        final contextTitle = contextModel.getFullTitle(context);
        final normalizedTitle =
            Utilities.removeDiacritics(contextTitle).toLowerCase();
        return normalizedTitle.contains(normalizedQuery);
      }).toList();
    });
  }

  // Helper to get the included model for a given context
  ProductInventoryContextModel? _getInclusion(
      InventoryContextModel contextModel) {
    try {
      return widget.product.includedInventories
          .firstWhere((p) => p.inventoryContextId == contextModel.id);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: InventoryStrings.inclusionSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              // _filterContexts already calls setState internally
              _filterContexts(value);
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _filteredAvailableContexts.length,
            itemBuilder: (context, index) {
              final currentContext = _filteredAvailableContexts[index];
              final inclusion =
                  _getInclusion(currentContext); // Use the local helper
              final isIncluded = inclusion != null;

              return Card(
                elevation: 1.5,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      // This setState now correctly rebuilds _InventoryDialogContent
                      if (isIncluded) {
                        widget.product.includedInventories.removeWhere(
                            (p) => p.inventoryContextId == currentContext.id);
                      } else {
                        widget.product.includedInventories
                            .add(ProductInventoryContextModel(
                          productId: widget.product.id!,
                          inventoryContextId: currentContext.id!,
                          quantity: 1,
                          inventoryContext: currentContext,
                        ));
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: isIncluded,
                          onChanged: (bool? value) {
                            setState(() {
                              // This setState now correctly rebuilds _InventoryDialogContent
                              if (value == true) {
                                widget.product.includedInventories
                                    .add(ProductInventoryContextModel(
                                  productId: widget.product.id!,
                                  inventoryContextId: currentContext.id!,
                                  quantity: 1,
                                  inventoryContext: currentContext,
                                ));
                              } else {
                                widget.product.includedInventories.removeWhere(
                                    (p) =>
                                        p.inventoryContextId ==
                                        currentContext.id);
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(currentContext.getFullTitle(context)),
                        ),
                        if (isIncluded)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () {
                                  if (inclusion.quantity > 1) {
                                    setState(() => inclusion
                                        .quantity--); // This setState now correctly rebuilds _InventoryDialogContent
                                  }
                                },
                              ),
                              Text(inclusion.quantity.toString(),
                                  style: const TextStyle(fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => setState(() => inclusion
                                    .quantity++), // This setState now correctly rebuilds _InventoryDialogContent
                              ),
                            ],
                          ),
                      ],
                    ),
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
