import 'package:flutter/material.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';

import 'default_value_helper.dart';
import 'description_with_edit.dart';
import 'form_fields_generator.dart';
import 'ticket_editor_widgets.dart';
import 'ticket_product_editor_row.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'description_tooltip.dart';

class ProductTypeEditorWidgets {
  /// Builds the read-only view for a product type group.
  static Widget buildProductTypeReadOnly(
      BuildContext context, FormFieldModel ptField) {
    ptField.productType ??=
        ProductTypeModel(title: ptField.title, products: []);
    final group = ptField.productType!;
    group.products ??= [];
    final groupHidden = ptField.isHidden ?? false;

    // NOTE: Removed filtering of hidden products. They will be shown with a strikethrough.

    final isSelectMany = ptField.data?[FormHelper.metaSelectionType] ==
        FormHelper.metaSelectionTypeMany;

    final requiredStar = (ptField.isRequired ?? false)
        ? TextSpan(
            text: ' *',
            style: TextStyle(color: ThemeConfig.redColor(context)),
          )
        : null;

    final groupTitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          decoration: groupHidden ? TextDecoration.lineThrough : null,
        );

    final showCapacityColumn =
        group.products!.any((product) => (product.maximum ?? 0) != 0);

    return Opacity(
      opacity: groupHidden ? kHiddenOpacity : 1.0,
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Title
              Row(
                children: [
                  RichText(
                    text: TextSpan(
                      text: ptField.productType?.title ?? group.title ?? '',
                      style: groupTitleStyle,
                      children: [if (requiredStar != null) requiredStar],
                    ),
                  ),
                  if (!HtmlHelper.isHtmlEmptyOrNull(
                      ptField.productType?.description))
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                      child: DescriptionTooltip(
                        description: ptField.productType!.description!,
                        child: const Icon(Icons.description, size: 16),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (group.products!.isEmpty)
                Text(FormStrings.noProducts)
              else ...[
                // Header Row for the product list
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      const SizedBox(width: 48), // Space for selection control
                      Expanded(
                        flex: 8,
                        child: Text(CommonStrings.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(CommonStrings.price,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      if (showCapacityColumn)
                        Expanded(
                          flex: 3,
                          child: Tooltip(
                            message: FormStrings.productQuantity,
                            child: Icon(Icons.stacked_bar_chart,
                                size: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color),
                          ),
                        ),
                    ],
                  ),
                ),
                // List of Products
                Column(
                  children: group.products!.map((product) {
                    // UPDATED: Logic to handle hidden product style
                    final productHidden = product.isHidden ?? false;
                    final rowStyle = TextStyle(
                      decoration:
                          productHidden ? TextDecoration.lineThrough : null,
                    );

                    return Opacity(
                      opacity: productHidden ? kHiddenOpacity : 1.0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            // Radio or Checkbox based on selection type
                            SizedBox(
                              width: 48,
                              child: isSelectMany
                                  ? Checkbox(value: false, onChanged: null)
                                  : Radio<String>(
                                      value: product.id.toString(),
                                      groupValue: null,
                                      onChanged: null),
                            ),
                            // Product title and description icon
                            Expanded(
                              flex: 8,
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      product.title ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: rowStyle, // Apply style
                                    ),
                                  ),
                                  if (!HtmlHelper.isHtmlEmptyOrNull(
                                      product.description))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 8.0, right: 4.0),
                                      child: DescriptionTooltip(
                                        description: product.description!,
                                        child: const Icon(Icons.description,
                                            size: 16),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Product price
                            Expanded(
                              flex: 3,
                              child: Text(
                                Utilities.formatPrice(
                                    context, product.price ?? 0,
                                    currencyCode: product.currencyCode),
                                style: rowStyle, // Apply style
                              ),
                            ),
                            // Product capacity
                            if (showCapacityColumn)
                              Expanded(
                                flex: 3,
                                child: Text(
                                  TicketEditorWidgets.formatOrderedCount(
                                      product.orderedCount, product.maximum),
                                  textAlign: TextAlign.center,
                                  style: rowStyle, // Apply style
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the editor for a product type group.
  static Widget buildProductTypeEditor(BuildContext context, FormModel form,
      FormFieldModel ptField, VoidCallback refresh) {
    // This static method now delegates to the new StatefulWidget.
    // A key is used to ensure Flutter correctly identifies the widget.
    return ProductTypeEditor(
      key: ValueKey(ptField.id ?? ptField.hashCode),
      form: form,
      ptField: ptField,
      refresh: refresh,
    );
  }

  // Helper for building compact controls
  static Widget _buildControl(
      BuildContext context, String label, Widget control) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        control,
      ],
    );
  }

  static void _removeProductFromDefault(FormFieldModel field, int? productId) {
    if (productId == null) return;
    DefaultValueHelper.remove(field, productId.toString());
  }

  /// Read-only indicator of the stored default product selection.
  static Widget _buildDefaultSelector({
    required FormFieldModel ptField,
    required ProductModel product,
    required bool isSelectMany,
  }) {
    final key = product.id?.toString();
    if (key == null) {
      // Unsaved product (no id yet) — placeholder spacer so layout aligns.
      return const SizedBox(width: 48);
    }
    if (isSelectMany) {
      final selected = DefaultValueHelper.readList(ptField).contains(key);
      return Checkbox(
        value: selected,
        onChanged: null,
      );
    }
    return Radio<String>(
      value: key,
      groupValue: DefaultValueHelper.readString(ptField),
      onChanged: null,
    );
  }
}

/// A stateful widget to manage the editor state for a product type.
class ProductTypeEditor extends StatefulWidget {
  final FormModel form;
  final FormFieldModel ptField;
  final VoidCallback refresh;

  const ProductTypeEditor({
    super.key,
    required this.form,
    required this.ptField,
    required this.refresh,
  });

  @override
  State<ProductTypeEditor> createState() => _ProductTypeEditorState();
}

class _ProductTypeEditorState extends State<ProductTypeEditor> {
  // The controller is now a state variable, initialized once.
  late final TextEditingController groupTitleController;

  @override
  void initState() {
    super.initState();
    // Initialize the controller in initState to prevent re-creation on build.
    widget.ptField.productType ??=
        ProductTypeModel(title: widget.ptField.title, products: []);
    groupTitleController = TextEditingController(
        text: widget.ptField.title ?? widget.ptField.productType!.title);
  }

  @override
  void dispose() {
    // Dispose the controller when the widget is removed from the tree.
    groupTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Logic from the original static method is now here.
    final form = widget.form;
    final ptField = widget.ptField;
    final refresh = widget.refresh;

    final group = ptField.productType!;
    group.products ??= [];

    final defaultDescription = CommonStrings.description;
    final groupIsRequired = ptField.isRequired ?? false;
    final groupIsHidden = ptField.isHidden ?? false;
    final hasDeposit = FeatureService.isFeatureEnabled(FeatureConstants.deposit);
    final canSelectMany = ptField.data?[FormHelper.metaSelectionType] ==
        FormHelper.metaSelectionTypeMany;

    return Opacity(
      opacity: groupIsHidden ? kHiddenOpacity : 1.0,
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with controls
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller:
                          groupTitleController, // Use the stateful controller
                      decoration: InputDecoration(
                          labelText: FormStrings.productTypeTitle,
                          border: const UnderlineInputBorder()),
                      onChanged: (val) {
                        // Update the model, but DO NOT call refresh().
                        // The controller handles the UI update.
                        ptField.title = val;
                        group.title = val;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ProductTypeEditorWidgets._buildControl(
                      context,
                      FormStrings.requiredLabel,
                      Checkbox(
                          value: groupIsRequired,
                          onChanged: (val) {
                            ptField.isRequired = val;
                            refresh();
                          })),
                  const SizedBox(width: 12),
                  ProductTypeEditorWidgets._buildControl(
                      context,
                      FormStrings.multipleChoice,
                      Switch(
                          value: canSelectMany,
                          onChanged: (val) {
                            ptField.data ??= {};
                            if (val) {
                              ptField.data![FormHelper.metaSelectionType] =
                                  FormHelper.metaSelectionTypeMany;
                            } else {
                              ptField.data!
                                  .remove(FormHelper.metaSelectionType);
                            }
                            refresh();
                          })),
                  const SizedBox(width: 12),
                  ProductTypeEditorWidgets._buildControl(
                      context,
                      FormStrings.show,
                      Switch(
                          value: !groupIsHidden,
                          onChanged: (val) {
                            ptField.isHidden = !val;
                            refresh();
                          })),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == "add_description") {
                        if (HtmlHelper.isHtmlEmptyOrNull(
                            ptField.productType!.description)) {
                          ptField.productType!.description = defaultDescription;
                        }
                        refresh();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                          value: "add_description",
                          child: Text(FormStrings.addDescription)),
                    ],
                    icon: const Icon(Icons.more_vert),
                  ),
                  IconButton(
                    tooltip: ptField.canDelete
                        ? CommonStrings.delete
                        : FormStrings.deletionReason(
                            ptField.deleteBlockedReason),
                    icon: const Icon(Icons.delete),
                    onPressed: !ptField.canDelete
                        ? null
                        : () {
                            form.removeField(ptField);
                            refresh();
                          },
                  ),
                ],
              ),
              // Description Editor
              if (!HtmlHelper.isHtmlEmptyOrNull(
                  ptField.productType?.description))
                DescriptionWithEdit(
                  description: ptField.productType!.description!,
                  defaultDescription: defaultDescription,
                  onDescriptionChanged: (newDescription) {
                    ptField.productType!.description = newDescription;
                    refresh();
                  },
                  occasionId: form.occasionId!,
                ),
              const SizedBox(height: 8),
              // List of Product Rows with leading default selector
              for (int i = 0; i < group.products!.length; i++)
                Container(
                  key: ObjectKey(group.products![i]),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: hasDeposit ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(vertical: 6),
                  decoration: hasDeposit ? BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ) : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductTypeEditorWidgets._buildDefaultSelector(
                        ptField: ptField,
                        product: group.products![i],
                        isSelectMany: canSelectMany,
                      ),
                      Expanded(
                        child: TicketProductEditorRow(
                          product: group.products![i],
                          onChanged: refresh,
                          onDelete: () {
                            final removed = group.products!.removeAt(i);
                            if (removed.id != null) {
                              form.deletedProductIds.add(removed.id!);
                            }
                            ProductTypeEditorWidgets._removeProductFromDefault(
                              ptField,
                              removed.id,
                            );
                            refresh();
                          },
                          availableCurrencies: form.getSupportedCurrencies(),
                        ),
                      ),
                    ],
                  ),
                ),
              // Add Product Button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    group.products!.add(
                      ProductModel(
                        title: FormStrings.newProduct,
                        price: 0.0,
                        isHidden: false,
                        order: (group.products!.isNotEmpty
                                ? group.products!.last.order ?? 0
                                : 0) +
                            1,
                      ),
                    );
                    refresh();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(FormStrings.addProduct),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
