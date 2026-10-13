import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart'; // Import ThemeConfig
import 'package:collection/collection.dart';
import '../blueprint_seat_state.dart';

import '../../_shared/common_strings.dart';

/// Dialog to select an existing spot product, or manage (edit/create) them.
class SelectProductDialog extends StatefulWidget {
  final BlueprintModel blueprint;
  final int? currentProductId; // To show selection

  const SelectProductDialog({
    super.key,
    required this.blueprint,
    this.currentProductId,
  });

  @override
  State<SelectProductDialog> createState() => _SelectProductDialogState();
}

class _SelectProductDialogState extends State<SelectProductDialog> {
  late List<ProductModel> _spotProducts;

  @override
  void initState() {
    super.initState();
    _spotProducts = widget.blueprint.spotProducts;
    _sortProducts();
  }

  void _sortProducts() {
    _spotProducts
        .sort((a, b) => Utilities.naturalCompare(a.title ?? "", b.title ?? ""));
  }

  /// Shows the EditProductDialog to create or update a product.
  void _editProduct(ProductModel? product) async {
    final bool isCreating = product == null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return EditProductDialog(
          product: product?.copyWith() ??
              ProductModel(
                title: "",
                price: 0.0,
                productTypeString: ProductModel.spotType, // Set valid type
              ),
          isCreating: isCreating,
        );
      },
    );

    if (result != null) {
      final newTitle = result['title'] as String;
      final newPrice = result['price'] as double;

      try {
        if (isCreating) {
          // Safety check: Cannot create a new spot product if we don't have a template
          if (_spotProducts.isEmpty) {
            ToastHelper.Show(
              context,
              BlueprintStrings.toastNoTemplateProduct,
              severity: ToastSeverity.NotOk,
            );
            return;
          }

          // Get details from an existing spot product
          final existingProduct = _spotProducts.first;

          final newProduct = ProductModel(
            title: newTitle,
            price: newPrice,
            currencyCode: existingProduct.currencyCode,
            productTypeId: existingProduct.productTypeId,
            occasion: existingProduct.occasion,
            productTypeString: ProductModel.spotType,
          );

          // Call DB to create, get new ID
          final newId = await DbEshop.updateProduct(newProduct);
          newProduct.id = newId;

          setState(() {
            widget.blueprint.products ??= [];
            widget.blueprint.products!.add(newProduct);
            _spotProducts = widget.blueprint.spotProducts;
            _sortProducts();
          });

          ToastHelper.Show(context, BlueprintStrings.productCreated,
              severity: ToastSeverity.Ok);
        } else {
          // Find the original product in the blueprint and update it
          final originalProduct = widget.blueprint.products
              ?.firstWhereOrNull((p) => p.id == product.id);
          if (originalProduct != null) {
            originalProduct.title = newTitle;
            originalProduct.price = newPrice;
            // productTypeId and productTypeString are not changing

            // Call DB to update
            await DbEshop.updateProduct(originalProduct);

            setState(() {
              // Refresh local list
              _spotProducts = widget.blueprint.spotProducts;
              _sortProducts();
            });

            ToastHelper.Show(context, BlueprintStrings.productUpdated,
                severity: ToastSeverity.Ok);
          }
        }
      } catch (e) {
        // Show error from DB call
        ToastHelper.Show(context, e.toString(), severity: ToastSeverity.NotOk);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(BlueprintStrings.selectProduct),
      content: SizedBox(
        width: 500, // Make it a bit wider
        child: _spotProducts.isEmpty
            ? Center(child: Text(BlueprintStrings.noSpotProducts))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _spotProducts.length,
                itemBuilder: (context, index) {
                  final product = _spotProducts[index];
                  // Check if this product is the selected one
                  final isSelected = product.id == widget.currentProductId;
                  return ListTile(
                    // Apply selected state
                    selected: isSelected,
                    selectedTileColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    title: Text(product.title ?? ""),
                    subtitle: Text(
                        Utilities.formatPrice(context, product.price ?? 0)),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: BlueprintStrings.editProduct,
                      onPressed: () => _editProduct(product),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(product); // Select the product
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(BlueprintStrings.createProduct),
          onPressed: () => _editProduct(null), // Pass null for creation
        ),
      ],
    );
  }
}

/// Dialog for editing/creating a single product
class EditProductDialog extends StatefulWidget {
  final ProductModel product;
  final bool isCreating;

  const EditProductDialog(
      {super.key, required this.product, required this.isCreating});

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _title;
  late double _price;
  final _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _title = widget.product.title ?? "";
    _price = widget.product.price ?? 0.0;
    _priceController.text = _price.toString();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      Navigator.of(context).pop({
        'title': _title,
        'price': _price,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isCreating
          ? BlueprintStrings.createProduct
          : BlueprintStrings.editProduct),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _title,
              decoration: InputDecoration(
                labelText: CommonStrings.title,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return CommonStrings.fieldCannotBeEmpty;
                }
                return null;
              },
              onSaved: (value) {
                _title = value!.trim();
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController, // Use controller for validation
              decoration: InputDecoration(
                labelText: CommonStrings.price,
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                // Allow digits, and at most one decimal point
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return CommonStrings.fieldCannotBeEmpty;
                }
                final price = double.tryParse(value);
                if (price == null || price < 0) {
                  return CommonStrings.invalidFormat;
                }
                return null;
              },
              onSaved: (value) {
                _price = double.tryParse(value!) ?? 0.0;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(CommonStrings.save),
        ),
      ],
    );
  }
}

/// Unified Dialog to manage both the Group Product and Individual Seat overrides.
class GroupProductManagerDialog extends StatefulWidget {
  final BlueprintModel blueprint;
  final BlueprintGroupModel group;

  const GroupProductManagerDialog({
    super.key,
    required this.blueprint,
    required this.group,
  });

  @override
  State<GroupProductManagerDialog> createState() =>
      _GroupProductManagerDialogState();
}

class _GroupProductManagerDialogState extends State<GroupProductManagerDialog> {
  bool _showIndividualList = false;

  // State for display
  bool _isUniform = false;
  ProductModel? _uniformProduct;

  @override
  void initState() {
    super.initState();
    _recalculateState();

    // If mixed, show list by default so user can see what's happening
    if (!_isUniform) {
      _showIndividualList = true;
    }
  }

  /// Check if all spots have the same product ID.
  void _recalculateState() {
    final objects = widget.group.objects;
    if (objects.isEmpty) {
      _isUniform = true;
      _uniformProduct = widget.group.product;
      return;
    }

    // Get the first product (fallback to group default if spot is null)
    final firstProduct = objects.first.product ?? widget.group.product;
    final firstId = firstProduct?.id;

    bool allMatch = true;
    for (var obj in objects) {
      final p = obj.product ?? widget.group.product;
      if (p?.id != firstId) {
        allMatch = false;
        break;
      }
    }

    setState(() {
      _isUniform = allMatch;
      _uniformProduct = allMatch ? firstProduct : null;
    });
  }

  bool _isOccupied(BlueprintObjectModel obj) {
    final state = obj.stateEnum;
    return state == BlueprintSeatState.ordered ||
        state == BlueprintSeatState.used ||
        state == BlueprintSeatState.selected ||
        state == BlueprintSeatState.selectedByMe;
  }

  Future<void> _pickProduct({BlueprintObjectModel? seat}) async {
    // Current ID for selection highlight
    final currentId = seat != null
        ? seat.product?.id
        : (_isUniform ? _uniformProduct?.id : null);

    final selectedProduct = await showDialog<ProductModel>(
      context: context,
      builder: (context) => SelectProductDialog(
        blueprint: widget.blueprint,
        currentProductId: currentId,
      ),
    );

    if (selectedProduct != null) {
      setState(() {
        if (seat != null) {
          // --- CASE A: Change Individual Seat ---
          seat.product = selectedProduct;
          seat.spotProduct = selectedProduct.id;

          // Re-check uniformity (user might have manually made them all same, or mixed them)
          _recalculateState();
        } else {
          // --- CASE B: Change Group Product (Master) ---
          // Apply this product to EVERY seat to enforce uniformity.
          widget.group.product =
              selectedProduct; // Update fallback just in case

          for (var obj in widget.group.objects) {
            obj.product = selectedProduct;
            obj.spotProduct = selectedProduct.id;
          }

          ToastHelper.Show(context, BlueprintStrings.productAssignedToAll,
              severity: ToastSeverity.Ok);

          _recalculateState();

          // Since it's now uniform, we can hide the list to declutter
          _showIndividualList = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sort seats by title for cleaner list
    final sortedObjects = List<BlueprintObjectModel>.from(widget.group.objects)
      ..sort((a, b) => Utilities.naturalCompare(a.title ?? "", b.title ?? ""));

    final hasOccupiedSeats = sortedObjects.any((obj) => _isOccupied(obj));

    // Display strings
    final groupProductTitle = _isUniform
        ? (_uniformProduct?.title ?? BlueprintStrings.noProductAssigned)
        : BlueprintStrings.mixedProducts;

    final groupProductPrice = (_isUniform && _uniformProduct != null)
        ? Utilities.formatPrice(context, _uniformProduct!.price ?? 0)
        : "";

    // Status visual colors using ThemeConfig
    final statusText = _isUniform
        ? BlueprintStrings.statusUniform
        : BlueprintStrings.statusMixed;

    // Use ThemeConfig.greenColor for "good" status, and orange for "mixed/warning".
    final Color statusColor = _isUniform
        ? ThemeConfig.greenColor(context)
        : (ThemeConfig.isDarkMode(context)
            ? Colors.orangeAccent
            : Colors.orange);

    // Warning color for occupied/mixed elements
    final Color warningColor =
        ThemeConfig.isDarkMode(context) ? Colors.orangeAccent : Colors.orange;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Text(
          "${BlueprintStrings.manageGroupProducts}: ${widget.group.title}"),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- SECTION 1: GROUP PRODUCT (Master Control) ---
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(BlueprintStrings.groupDefaultProduct,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        "${BlueprintStrings.currentProductPrefix}$groupProductTitle $groupProductPrice"),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                            _isUniform
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            size: 14,
                            color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    )
                  ],
                ),
                trailing: const Icon(Icons.edit),
                onTap: () => _pickProduct(seat: null),
              ),
            ),

            const SizedBox(height: 12),

            // --- TOGGLE FOR INDIVIDUAL SEATS ---
            // Force enabled if mixed, otherwise toggleable
            Row(
              children: [
                Switch(
                  value: _showIndividualList || !_isUniform,
                  onChanged: _isUniform
                      ? (val) {
                          setState(() {
                            _showIndividualList = val;
                          });
                        }
                      : null, // Disable toggle if mixed (must show list)
                ),
                const SizedBox(width: 8),
                Text(BlueprintStrings.customizeIndividualSeats),
              ],
            ),

            const Divider(),

            // --- SECTION 2: INDIVIDUAL SEATS ---
            Expanded(
              child: (_showIndividualList || !_isUniform)
                  ? ListView.separated(
                      itemCount: sortedObjects.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final obj = sortedObjects[index];
                        final isOccupied = _isOccupied(obj);

                        // Resolve effective product (fallback to group if null, though we try to set it)
                        final displayProduct =
                            obj.product ?? widget.group.product;
                        final productTitle = displayProduct?.title ??
                            BlueprintStrings.noProductAssigned;
                        final productPrice = displayProduct != null
                            ? Utilities.formatPrice(
                                context, displayProduct.price ?? 0)
                            : "";

                        return Container(
                          color: isOccupied
                              ? warningColor.withOpacity(0.05)
                              : null,
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Icon(
                              isOccupied ? Icons.lock_clock : Icons.event_seat,
                              color: isOccupied ? warningColor : Colors.grey,
                              size: 20,
                            ),
                            title: Text(
                              obj.title ??
                                  "", // Shows only Seat Title (e.g., "A1")
                              style: const TextStyle(fontSize: 16),
                            ),
                            subtitle: Text(
                              "$productTitle ($productPrice)",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: ThemeConfig.grey600(context)),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: BlueprintStrings.editProduct,
                              onPressed: () => _pickProduct(seat: obj),
                            ),
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.format_list_bulleted,
                                size: 48,
                                color: Theme.of(context).disabledColor),
                            const SizedBox(height: 16),
                            Text(
                              BlueprintStrings.uniformViewHelp,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (hasOccupiedSeats)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            width: double.infinity,
            color: warningColor.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: warningColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    BlueprintStrings.occupiedWarningInline,
                    style: TextStyle(
                        fontSize: 13,
                        color: warningColor.withOpacityUniversal(context, 1.0)),
                  ),
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.close),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    );
  }
}
