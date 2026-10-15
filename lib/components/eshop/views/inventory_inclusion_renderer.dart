import 'package:collection/collection.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/services/utilities_all.dart';

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
  List<ProductInventoryContextModel> get inclusions =>
      (widget.rendererContext.cell.value as List)
          .cast<ProductInventoryContextModel>();

  Future<void> _showInventoryDialog(BuildContext context) async {
    final before = [...inclusions];
    final draft = [...before];

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AppAlertDialog(
          onClose: () => Navigator.of(dialogContext).pop(),
          // MODIFIED LINE: Added the product title to the dialog title
          title: Text(InventoryStrings.inclusionManageTitle(
              widget.product.title ?? "")),
          content: SizedBox(
            // Set max width for the dialog content
            width: StylesConfig.formMaxWidthMid,
            // The dialog content is now its own StatefulWidget
            child: _InventoryDialogContent(
              product: widget.product,
              inclusions: draft,
              availableContexts: widget.availableContexts,
            ),
          ),
          actions: [],
        );
      },
    );

    if (!mounted) return;
    if (!const ListEquality().equals(before, draft)) {
      widget.rendererContext.stateManager.changeCellValue(
          widget.rendererContext.cell,
          List<ProductInventoryContextModel>.unmodifiable(draft),
          force: true);
      setState(() {});
    }
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
              children: inclusions.map((link) {
                final quantityText =
                    link.quantity > 1 ? " (x${link.quantity})" : "";
                final labelText =
                    "${widget.availableContexts.firstWhereOrNull((item) => item.id == link.inventoryContextId)?.getFullTitle(context) ?? '...'}$quantityText";

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
  final List<ProductInventoryContextModel> inclusions;
  final List<InventoryContextModel> availableContexts;

  const _InventoryDialogContent({
    required this.product,
    required this.inclusions,
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
      return widget.inclusions
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
                        widget.inclusions.removeWhere(
                            (p) => p.inventoryContextId == currentContext.id);
                      } else {
                        widget.inclusions.add(ProductInventoryContextModel(
                          productId: widget.product.id!,
                          inventoryContextId: currentContext.id!,
                          quantity: 1,
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
                                widget.inclusions
                                    .add(ProductInventoryContextModel(
                                  productId: widget.product.id!,
                                  inventoryContextId: currentContext.id!,
                                  quantity: 1,
                                ));
                              } else {
                                widget.inclusions.removeWhere((p) =>
                                    p.inventoryContextId == currentContext.id);
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
                                    setState(() => widget.inclusions[
                                        widget.inclusions.indexOf(
                                            inclusion)] = inclusion.copyWith(
                                        quantity: inclusion.quantity -
                                            1)); // This setState now correctly rebuilds _InventoryDialogContent
                                  }
                                },
                              ),
                              Text(inclusion.quantity.toString(),
                                  style: const TextStyle(fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => setState(() => widget
                                        .inclusions[
                                    widget.inclusions.indexOf(
                                        inclusion)] = inclusion.copyWith(
                                    quantity: inclusion.quantity +
                                        1)), // This setState now correctly rebuilds _InventoryDialogContent
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
