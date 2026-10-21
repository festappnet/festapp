import 'package:collection/collection.dart';
import 'package:festapp_core/eshop.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../blueprint_layout_controller.dart';
import '../blueprint_standing_inventory.dart';
import '../blueprint_strings.dart';
import 'blueprint_product_dialogs.dart';

/// Catalog/inventory preparation is immediate; the binding remains a plan draft.
class BlueprintStandingSetupDialog extends StatefulWidget {
  const BlueprintStandingSetupDialog({
    super.key,
    required this.controller,
    required this.nodeId,
    required this.occasionLink,
  });
  final BlueprintLayoutController controller;
  final String nodeId;
  final String occasionLink;
  @override
  State<BlueprintStandingSetupDialog> createState() => _StandingSetupState();
}

class _StandingSetupState extends State<BlueprintStandingSetupDialog> {
  ProductsEditBundle? catalog;
  ProductModel? product;
  InventoryContextModel? inventory;
  final preparations = <int, BlueprintStandingInventory>{};
  BlueprintStandingInventory get preparation => preparations.putIfAbsent(
        product!.id!,
        () => BlueprintStandingInventory(),
      );
  bool busy = true;
  String? error;
  late final capacity = TextEditingController(
    text: widget.controller.areaCapacity(widget.nodeId).toString(),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    capacity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loaded = await DbEshop.getProductsAndTypesForOccasion(
        widget.occasionLink,
      );
      if (mounted)
        setState(() {
          catalog = loaded;
          busy = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = e.toString();
          busy = false;
        });
    }
  }

  List<InventoryContextModel> contexts(ProductModel p) => [
        for (final link in p.includedInventories)
          if (link.quantity == 1)
            for (final c in catalog!.inventoryContexts)
              if (c.id == link.inventoryContextId &&
                  c.inventoryPool?.sellableCapacity != null &&
                  !widget.controller.snapshot.areaBindings.values.any(
                    (binding) => binding.inventoryContextId == c.id,
                  ))
                c,
      ];

  bool eligible(ProductModel p) =>
      p.id != null &&
      p.occasion == widget.controller.snapshot.occasionId &&
      p.productTypeString == ProductModel.spotType &&
      p.isHidden != true &&
      p.price != null &&
      (contexts(p).isNotEmpty ||
          (p.includedInventories.isEmpty && (p.orderedCount ?? 0) == 0));

  void choose(ProductModel p) {
    final options = contexts(p);
    setState(() {
      product = p;
      inventory = options.length == 1 ? options.single : null;

      error = null;
      capacity.text = (preparation.preparedCapacity ??
              inventory?.inventoryPool?.sellableCapacity ??
              widget.controller.areaCapacity(widget.nodeId))
          .toString();
    });
  }

  Future<void> createProduct() async {
    final type = catalog!.productTypes.firstWhereOrNull(
      (t) =>
          t.type == ProductModel.spotType &&
          t.occasion == widget.controller.snapshot.occasionId,
    );
    if (type == null) {
      setState(() => error = BlueprintStrings.standingNoAdmissionType);
      return;
    }
    final template = catalog!.products.firstWhereOrNull(
      (p) => p.productTypeId == type.id,
    );
    final draft = ProductModel(
      title: '',
      price: 0,
      occasion: widget.controller.snapshot.occasionId,
      productTypeId: type.id,
      productTypeString: ProductModel.spotType,
      currencyCode: template?.currencyCode ?? 'CZK',
    );
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EditProductDialog(product: draft, isCreating: true),
    );
    if (result == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await DbEshop.saveProductBasics(
        draft.copyWith(
          title: result['title'] as String,
          price: result['price'] as double,
        ),
      );
      widget.controller.upsertCatalogProduct(saved);
      if (!mounted) return;
      catalog!.products.add(saved);
      choose(saved);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editProduct(ProductModel selected) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          EditProductDialog(product: selected.copyWith(), isCreating: false),
    );
    if (result == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await DbEshop.saveProductBasics(selected.copyWith(
          title: result['title'] as String, price: result['price'] as double));
      widget.controller.upsertCatalogProduct(saved);
      if (!mounted) return;
      final index = catalog!.products.indexWhere((p) => p.id == saved.id);
      catalog!.products[index] = saved;
      if (product?.id == saved.id) product = saved;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> assign() async {
    final p = product;
    final count = int.tryParse(capacity.text);
    if (p == null || count == null || count < 0 || count > 1000000) {
      setState(() => error = BlueprintStrings.invalidStandingCapacity);
      return;
    }
    if (p.includedInventories.isNotEmpty && inventory == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var linked = p;
      var contextId = inventory?.id;
      if (contextId == null) {
        linked = await preparation.prepare(p, count);
        contextId = linked.includedInventories.single.inventoryContextId;
        // Linking inventory increments the product aggregate. Use the returned
        // catalog projection for later product edits, rather than a stale version.
        final refreshed = await DbEshop.getProductsAndTypesForOccasion(
          widget.occasionLink,
        );
        linked = refreshed.products.firstWhere((item) => item.id == p.id);
      }
      widget.controller.bindStandingArea(
        widget.nodeId,
        linked,
        inventoryContextId: contextId,
        capacity: count,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
        dismissible: !busy,
        onClose: () => Navigator.of(context).pop(),
        title: Text(BlueprintStrings.assignStandingProduct),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(BlueprintStrings.standingSetupSaveHint),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (catalog != null) ...[
                  const SizedBox(height: 16),
                  BlueprintProductOptions(
                    products: catalog!.products.where(eligible).toList(),
                    currentProductId: product?.id,
                    onSelected: busy ? null : choose,
                    onEdit: busy ? null : editProduct,
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : createProduct,
                    icon: const Icon(Icons.add),
                    label: Text(BlueprintStrings.createProduct),
                  ),
                  if (product != null && contexts(product!).length > 1)
                    DropdownButtonFormField<int>(
                      value: inventory?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: BlueprintStrings.standingCapacityGroup,
                      ),
                      items: [
                        for (final c in contexts(product!))
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.getFullTitle(context),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (id) => setState(() {
                                inventory = contexts(product!)
                                    .firstWhere((c) => c.id == id);
                                capacity.text = inventory!
                                    .inventoryPool!.sellableCapacity
                                    .toString();
                              }),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: capacity,
                    enabled: !busy &&
                        product != null &&
                        preparation.preparedCapacity == null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: BlueprintStrings.standingCapacity,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (inventory != null) ...[
                    Text(BlueprintStrings.standingSharedCapacityHint),
                    Text(BlueprintStrings.standingSupplyHint),
                  ],
                  if (product != null && preparation.preparedCapacity != null)
                    Text(BlueprintStrings.standingPreparationRetained),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: Text(CommonStrings.storno),
          ),
          FilledButton(
            onPressed: busy ||
                    product == null ||
                    (product!.includedInventories.isNotEmpty &&
                        inventory == null)
                ? null
                : assign,
            child: Text(BlueprintStrings.assignStandingProduct),
          ),
        ],
      );
}
