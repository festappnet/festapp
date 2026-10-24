import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';

import 'description_with_edit.dart';
import 'form_fields_generator.dart';
import 'ticket_editor_widgets.dart';
import 'ticket_product_editor_row.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'description_tooltip.dart';

class ProductTypeEditorWidgets {
  /// Builds the read-only view for a product type group.
  static Widget buildProductTypeReadOnly(
      BuildContext context, FormFieldDraft ptField) {
    final group = ptField.definition.productType ??
        ProductTypeModel(title: ptField.definition.title, products: []);
    final products = group.products ?? const <ProductModel>[];
    final groupHidden = ptField.definition.isHidden ?? false;

    // NOTE: Removed filtering of hidden products. They will be shown with a strikethrough.

    final isSelectMany =
        ptField.definition.data?[FormMetadata.metaSelectionType] ==
            FormMetadata.metaSelectionTypeMany;

    final requiredStar = (ptField.definition.isRequired ?? false)
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
        products.any((product) => (product.maximum ?? 0) != 0);

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
                      text: ptField.definition.productType?.title ??
                          group.title ??
                          '',
                      style: groupTitleStyle,
                      children: [if (requiredStar != null) requiredStar],
                    ),
                  ),
                  if (!HtmlHelper.isHtmlEmptyOrNull(
                      ptField.definition.productType?.description))
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                      child: DescriptionTooltip(
                        description:
                            ptField.definition.productType!.description!,
                        child: const Icon(Icons.description, size: 16),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (products.isEmpty)
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
                  children: products.map((product) {
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
  static Widget buildProductTypeEditor(BuildContext context,
      FormEditorDraft form, FormFieldDraft ptField, VoidCallback refresh) {
    // This static method now delegates to the new StatefulWidget.
    // A key is used to ensure Flutter correctly identifies the widget.
    return ProductTypeEditor(
      key: ValueKey(ptField.definition.id ?? ptField.hashCode),
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

  static void _removeProductFromDefault(FormFieldDraft field, int? productId) {
    if (productId == null) return;
    field.definition = field.definition.copyWith(
        data: DefaultValueHelper.remove(
            field.definition.data, productId.toString()));
  }

  /// Edits the stored default product selection.
  static Widget _buildDefaultSelector({
    required FormFieldDraft ptField,
    required ProductModel product,
    required bool isSelectMany,
    required VoidCallback onChanged,
  }) {
    final key = product.id?.toString();
    if (key == null) {
      // Unsaved product (no id yet) — placeholder spacer so layout aligns.
      return const SizedBox(width: 48);
    }
    if (isSelectMany) {
      final selected =
          DefaultValueHelper.readList(ptField.definition.data).contains(key);
      return Checkbox(
        value: selected,
        onChanged: (value) {
          ptField.definition = ptField.definition.copyWith(
              data: DefaultValueHelper.toggleInList(
                  ptField.definition.data, key, value ?? false));
          onChanged();
        },
      );
    }
    return Radio<String>(
      value: key,
      groupValue: DefaultValueHelper.readString(ptField.definition.data),
      toggleable: true,
      onChanged: (value) {
        ptField.definition = ptField.definition.copyWith(
            data: DefaultValueHelper.write(ptField.definition.data, value));
        onChanged();
      },
    );
  }
}

/// A stateful widget to manage the editor state for a product type.
class ProductTypeEditor extends StatefulWidget {
  final FormEditorDraft form;
  final FormFieldDraft ptField;
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
  final _productKeys = <Object>[];

  // The controller is now a state variable, initialized once.
  late final TextEditingController groupTitleController;

  @override
  void initState() {
    super.initState();
    // Initialize the controller in initState to prevent re-creation on build.
    widget.ptField.definition = widget.ptField.definition.copyWith(
        productType: widget.ptField.definition.productType ??
            ProductTypeModel(
                title: widget.ptField.definition.title, products: []));
    if (widget.ptField.definition.productType!.products == null) {
      widget.ptField.definition = widget.ptField.definition.copyWith(
          productType: widget.ptField.definition.productType!
              .copyWith(products: <ProductModel>[]));
    }
    groupTitleController = TextEditingController(
        text: widget.ptField.definition.title ??
            widget.ptField.definition.productType!.title);
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

    final group = ptField.definition.productType!;
    while (_productKeys.length < group.products!.length) {
      _productKeys.add(Object());
    }

    final defaultDescription = CommonStrings.description;
    final groupIsRequired = ptField.definition.isRequired ?? false;
    final groupIsHidden = ptField.definition.isHidden ?? false;
    final canSelectMany =
        ptField.definition.data?[FormMetadata.metaSelectionType] ==
            FormMetadata.metaSelectionTypeMany;

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
                        ptField.definition =
                            ptField.definition.copyWith(title: val);
                        ptField.definition = ptField.definition.copyWith(
                            productType: ptField.definition.productType!
                                .copyWith(title: val));
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
                            ptField.definition =
                                ptField.definition.copyWith(isRequired: val);
                            refresh();
                          })),
                  const SizedBox(width: 12),
                  ProductTypeEditorWidgets._buildControl(
                      context,
                      FormStrings.multipleChoice,
                      Switch(
                          value: canSelectMany,
                          onChanged: (val) {
                            ptField.definition = ptField.definition
                                .copyWith(data: ptField.definition.data ?? {});
                            if (val) {
                              ptField.definition =
                                  ptField.definition.copyWith(data: {
                                ...?ptField.definition.data,
                                FormMetadata.metaSelectionType:
                                    FormMetadata.metaSelectionTypeMany
                              });
                            } else {
                              final data = <String, dynamic>{
                                ...?ptField.definition.data
                              }..remove(FormMetadata.metaSelectionType);
                              ptField.definition =
                                  ptField.definition.copyWith(data: data);
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
                            ptField.definition =
                                ptField.definition.copyWith(isHidden: !val);
                            refresh();
                          })),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == "add_description") {
                        if (HtmlHelper.isHtmlEmptyOrNull(
                            ptField.definition.productType!.description)) {
                          ptField.definition = ptField.definition.copyWith(
                              productType: ptField.definition.productType!
                                  .copyWith(description: defaultDescription));
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
                    tooltip: ptField.definition.canDelete
                        ? CommonStrings.delete
                        : FormStrings.deletionReason(
                            ptField.definition.deleteBlockedReason),
                    icon: const Icon(Icons.delete),
                    onPressed: !ptField.definition.canDelete
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
                  ptField.definition.productType?.description))
                DescriptionWithEdit(
                  description: ptField.definition.productType!.description!,
                  defaultDescription: defaultDescription,
                  onDescriptionChanged: (newDescription) {
                    ptField.definition = ptField.definition.copyWith(
                        productType: ptField.definition.productType!
                            .copyWith(description: newDescription));
                    refresh();
                  },
                  occasionId: form.definition.occasionId!,
                ),
              const SizedBox(height: 8),
              // List of Product Rows with leading default selector
              for (int i = 0; i < group.products!.length; i++)
                Container(
                  key: ObjectKey(_productKeys[i]),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductTypeEditorWidgets._buildDefaultSelector(
                        ptField: ptField,
                        product: group.products![i],
                        isSelectMany: canSelectMany,
                        onChanged: () {
                          setState(() {});
                          refresh();
                        },
                      ),
                      Expanded(
                        child: TicketProductEditorRow(
                          readProduct: () =>
                              ptField.definition.productType!.products![i],
                          replaceProduct: (product) {
                            final products = [
                              ...ptField.definition.productType!.products!
                            ]..[i] = product;
                            ptField.definition = ptField.definition.copyWith(
                                productType: ptField.definition.productType!
                                    .copyWith(products: products));
                          },
                          onChanged: refresh,
                          onDelete: () {
                            final products = [
                              ...ptField.definition.productType!.products!
                            ];
                            final removed = products.removeAt(i);
                            _productKeys.removeAt(i);
                            ptField.definition = ptField.definition.copyWith(
                                productType: ptField.definition.productType!
                                    .copyWith(products: products));
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
                    ptField.definition = ptField.definition.copyWith(
                        productType:
                            ptField.definition.productType!.copyWith(products: [
                      ...ptField.definition.productType!.products!,
                      ProductModel(
                        title: FormStrings.newProduct,
                        price: 0.0,
                        isHidden: false,
                        order: (group.products!.isNotEmpty
                                ? group.products!.last.order ?? 0
                                : 0) +
                            1,
                      ),
                    ]));
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
