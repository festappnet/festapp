import 'package:festapp_core/forms.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'dart:math';
import 'package:fstapp/app_config.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import '../form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'product_type_editor.dart';

class TicketEditorWidgets {
  static String formatOrderedCount(int? orderedCount, int? maximum) {
    final count = orderedCount ?? 0;
    final maxStr = (maximum != null && maximum != 0) ? maximum.toString() : '∞';
    return '$count / $maxStr';
  }

  static String _emptyProductTypesMessage(FormEditorDraft form) =>
      form.usesSeatSelection
          ? FormStrings.productsInBlueprint
          : FormStrings.noProductTypes;

  /// Helper to get the `max_tickets` value, defaulting to 1.
  static int _getMaxTickets(FormFieldDraft ticketField) {
    ticketField.definition = ticketField.definition
        .copyWith(data: ticketField.definition.data ?? {});
    int currentValue = 1;
    dynamic rawValue = ticketField.definition.data![FormMetadata.maxTickets];
    if (rawValue is int) {
      currentValue = rawValue;
    } else if (rawValue is String) {
      currentValue = int.tryParse(rawValue) ?? 1;
    }
    return currentValue.clamp(1, AppConfig.maxTicketsPerOrder);
  }

  static Widget buildTicketEditorReadOnly(
      BuildContext context, FormEditorDraft form, FormFieldDraft ticketField) {
    List<Widget> children = [];
    if (FeatureService.isFeatureEnabled(FeatureConstants.blueprint)) {
      children.add(buildSpotFieldReadOnly(context, form));
      children.add(const SizedBox(height: 8));
    }

    // Show "Max tickets per order" only if ticket feature be enabled.
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      children.add(_buildMaxTicketsReadOnly(context, ticketField));
      children.add(const SizedBox(height: 8));
    }

    final productTypeFields = form.relatedFields
        .where((f) =>
            f.definition.isTicketField == true &&
            f.definition.type == FormMetadata.fieldTypeProductType &&
            (f.definition.productType?.type != ProductModel.spotType ||
                !form.usesSeatSelection))
        .toList();
    if (productTypeFields.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          _emptyProductTypesMessage(form),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ));
    } else {
      productTypeFields.sort((a, b) =>
          (a.definition.order ?? 0).compareTo(b.definition.order ?? 0));
      for (var ptField in productTypeFields) {
        children.add(ProductTypeEditorWidgets.buildProductTypeReadOnly(
            context, ptField));
        children.add(const SizedBox(height: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  static Widget buildTicketEditor(
      BuildContext context,
      FormEditorDraft form,
      FormFieldDraft ticketField, // <-- This parameter was added
      List<ProductTypeModel> allProductTypes,
      VoidCallback refresh) {
    List<Widget> children = [];
    if (FeatureService.isFeatureEnabled(FeatureConstants.blueprint)) {
      children.add(buildSpotFieldEditor(context, form, () {
        if (!form.usesSeatSelection) {
          for (final productType in allProductTypes
              .where((type) => type.type == ProductModel.spotType)) {
            final alreadyAdded = form.relatedFields.any((field) =>
                field.definition.isTicketField == true &&
                field.definition.type == FormMetadata.fieldTypeProductType &&
                (identical(field.definition.productType, productType) ||
                    (productType.id != null &&
                        field.definition.productType?.id == productType.id)));
            if (!alreadyAdded) {
              _addExistingProductType(form, productType);
            }
          }
        }
        refresh();
      }));
      children.add(const SizedBox(height: 16));
    }

    // Show "Max tickets per order" only if ticket feature be enabled.
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      children.add(_buildMaxTicketsEditor(context, ticketField, refresh));
      children.add(const SizedBox(height: 24));
    }

    final productTypeFields = form.relatedFields
        .where((f) =>
            f.definition.isTicketField == true &&
            f.definition.type == FormMetadata.fieldTypeProductType &&
            (f.definition.productType?.type != ProductModel.spotType ||
                !form.usesSeatSelection))
        .toList();
    productTypeFields.sort(
        (a, b) => (a.definition.order ?? 0).compareTo(b.definition.order ?? 0));
    children.add(Text(
      FormStrings.productTypes,
      style: Theme.of(context).textTheme.titleSmall,
    ));
    children.add(const SizedBox(height: 8));
    if (productTypeFields.isEmpty) {
      children.add(Text(
        _emptyProductTypesMessage(form),
        style: Theme.of(context).textTheme.bodyMedium,
      ));
      children.add(const SizedBox(height: 16));
    }
    for (var ptField in productTypeFields) {
      children.add(ProductTypeEditorWidgets.buildProductTypeEditor(
          context, form, ptField, refresh));
      children.add(const SizedBox(height: 16));
    }
    children.add(Row(
      children: [
        const Spacer(),
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(FormStrings.addProductTypeTitle),
          onPressed: () async {
            final existingPtIds = form.relatedFields
                .where((f) =>
                    f.definition.isTicketField == true &&
                    f.definition.type == FormMetadata.fieldTypeProductType &&
                    f.definition.productType != null)
                .map((f) => f.definition.productType!.id)
                .toSet();

            final availableProductTypes = allProductTypes
                .where((pt) =>
                    (pt.type != ProductModel.spotType ||
                        !form.usesSeatSelection) &&
                    !existingPtIds.contains(pt.id))
                .toList();

            dynamic result;
            if (availableProductTypes.isEmpty) {
              result = '__CREATE_NEW__';
            } else {
              result = await _showAddProductTypeDialog(
                  context, availableProductTypes);
            }

            if (result == null) return;

            if (result is String && result == '__CREATE_NEW__') {
              _createNewProductType(form);
            } else if (result is ProductTypeModel) {
              _addExistingProductType(form, result);
            }
            refresh();
          },
        ),
      ],
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Builds the editor for the "max_tickets" setting
  static Widget _buildMaxTicketsEditor(
      BuildContext context, FormFieldDraft ticketField, VoidCallback refresh) {
    final cappedLimit = _getMaxTickets(ticketField);
    ticketField.definition = ticketField.definition.copyWith(data: {
      ...?ticketField.definition.data,
      FormMetadata.maxTickets: cappedLimit
    });
    bool showDeposit =
        ticketField.definition.data?[TicketHolder.metaShowDepositDescription] ??
            true;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: _getMaxTickets(ticketField).toString(),
              decoration: InputDecoration(
                labelText: FormStrings.labelMaxTicketsPerOrder,
                helperText:
                    '${FormStrings.helperMaxTicketsPerOrder} (1-${AppConfig.maxTicketsPerOrder})',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final number = int.tryParse(newValue.text);
                  return number != null && number > AppConfig.maxTicketsPerOrder
                      ? oldValue
                      : newValue;
                })
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return FormStrings.validationMaxTicketsInvalid;
                }
                final number = int.tryParse(value);
                if (number == null ||
                    number < 1 ||
                    number > AppConfig.maxTicketsPerOrder) {
                  return FormStrings.validationMaxTicketsInvalid;
                }
                return null; // Valid
              },
              onChanged: (value) {
                final number = int.tryParse(value);
                ticketField.definition = ticketField.definition
                    .copyWith(data: ticketField.definition.data ?? {});
                if (number != null &&
                    number >= 1 &&
                    number <= AppConfig.maxTicketsPerOrder) {
                  ticketField.definition = ticketField.definition.copyWith(
                      data: {
                        ...?ticketField.definition.data,
                        FormMetadata.maxTickets: number
                      });
                } else {
                  // If user clears the field or enters 0, default back to 1
                  ticketField.definition = ticketField.definition.copyWith(
                      data: {
                        ...?ticketField.definition.data,
                        FormMetadata.maxTickets: 1
                      });
                }
              },
            ),
          ),
          if (FeatureService.isFeatureEnabled(FeatureConstants.deposit)) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'deposit') {
                  ticketField.definition = ticketField.definition.copyWith(data: {
                    ...?ticketField.definition.data,
                    TicketHolder.metaShowDepositDescription: !showDeposit
                  });
                  refresh();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                CheckedPopupMenuItem<String>(
                  value: 'deposit',
                  checked: showDeposit,
                  child: Text(FormStrings.showDepositDescription),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the read-only display for the "max_tickets" setting
  static Widget _buildMaxTicketsReadOnly(
      BuildContext context, FormFieldDraft ticketField) {
    final int maxTickets = _getMaxTickets(ticketField);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        // This layout places the label on the left and the number on the right.
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            FormStrings.labelMaxTicketsPerOrder,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 8),
          Text(
            maxTickets.toString(),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static void _createNewProductType(FormEditorDraft form) {
    final newProductTypeField = FormFieldDraft(
      title: FormStrings.newProductTypeDefaultName,
      type: FormMetadata.fieldTypeProductType,
      isTicketField: true,
      productType: ProductTypeModel(
        title: FormStrings.newProductTypeDefaultName,
        products: [],
      ),
      order: (form.relatedFields
              .map((x) => x.definition.order ?? 0)
              .fold(0, max)) +
          1,
    );
    form.relatedFields.add(newProductTypeField);
  }

  static void _addExistingProductType(
      FormEditorDraft form, ProductTypeModel productType) {
    final newProductTypeField = FormFieldDraft(
      title: productType.title,
      type: FormMetadata.fieldTypeProductType,
      isTicketField: true,
      productType: productType,
      // Apply the first-position default only when adding a seat section.
      // Existing sections retain their saved/manual order.
      order: productType.type == ProductModel.spotType
          ? form.relatedFields
                  .where((field) => field.definition.isTicketField == true)
                  .map((field) => field.definition.order ?? 0)
                  .fold(0, min) -
              1
          : (form.relatedFields
                  .map((x) => x.definition.order ?? 0)
                  .fold(0, max)) +
              1,
    );
    form.relatedFields.add(newProductTypeField);
  }

  static Future<dynamic> _showAddProductTypeDialog(BuildContext context,
      List<ProductTypeModel> availableProductTypes) async {
    return showDialog<dynamic>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AppDialog(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDialogHeader(
                    title: Text(FormStrings.addProductTypeTitle,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.add_circle_outline),
                          title: Text(FormStrings.createNewProductTypeOption),
                          onTap: () =>
                              Navigator.of(dialogContext).pop('__CREATE_NEW__'),
                        ),
                        const Divider(),
                        ...availableProductTypes.map((pt) {
                          return ListTile(
                            leading: const Icon(Icons.category_outlined),
                            title: Text(
                                pt.title ?? FormStrings.untitledProductType),
                            onTap: () => Navigator.of(dialogContext).pop(pt),
                          );
                        })
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(CommonStrings.storno),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget buildSpotFieldEditor(
      BuildContext context, FormEditorDraft form, VoidCallback refresh) {
    var spotField = form.relatedFields.firstWhereOrNull((f) =>
        f.definition.isTicketField == true &&
        f.definition.type == FormMetadata.fieldTypeSpot);
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(FormHelper.fieldTypeIcons[FormMetadata.fieldTypeSpot]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                FormStrings.seatSelection,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: !(spotField?.definition.isHidden ?? true),
              onChanged: (val) {
                if (val) {
                  if (spotField == null) {
                    spotField = FormFieldDraft(
                      type: FormMetadata.fieldTypeSpot,
                      isTicketField: true,
                      isHidden: false,
                      order: form.relatedFields
                              .where((field) =>
                                  field.definition.isTicketField == true)
                              .map((field) => field.definition.order ?? 0)
                              .fold(0, min) -
                          1,
                    );
                    form.relatedFields.add(spotField!);
                  }
                  spotField!.definition =
                      spotField!.definition.copyWith(isHidden: false);
                } else {
                  var field = form.relatedFields.firstWhereOrNull((f) =>
                      f.definition.isTicketField == true &&
                      f.definition.type == FormMetadata.fieldTypeSpot);
                  if (field != null) {
                    field.definition =
                        field.definition.copyWith(isHidden: true);
                  }
                }
                refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildSpotFieldReadOnly(
      BuildContext context, FormEditorDraft form) {
    bool spotExists = form.relatedFields.any((f) =>
        f.definition.isTicketField == true &&
        f.definition.type == FormMetadata.fieldTypeSpot &&
        !(f.definition.isHidden ?? false));
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(FormHelper.fieldTypeIcons[FormMetadata.fieldTypeSpot]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                FormStrings.seatSelection,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: spotExists,
              onChanged: null,
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildTicketNoteCheckbox(
      BuildContext context, FormEditorDraft form, VoidCallback refresh) {
    final noteFieldIndex = form.relatedFields.indexWhere((f) =>
        f.definition.isTicketField == true &&
        f.definition.type == FormMetadata.fieldTypeNote &&
        !(f.definition.isHidden ?? true));
    final noteExists = noteFieldIndex != -1;
    return Checkbox(
      value: noteExists,
      onChanged: (val) {
        _toggleTicketNote(form, val ?? false);
        refresh();
      },
    );
  }

  static void _toggleTicketNote(FormEditorDraft form, bool val) {
    var ticketNote = form.relatedFields.firstWhereOrNull((f) =>
        f.definition.isTicketField == true &&
        f.definition.type == FormMetadata.fieldTypeNote);
    if (val) {
      if (ticketNote == null) {
        final newNoteField = FormFieldDraft(
          title: FormStrings.note,
          type: FormMetadata.fieldTypeNote,
          isTicketField: true,
          isHidden: false,
          order: (form.relatedFields
                  .map((x) => x.definition.order ?? 0)
                  .fold(0, max)) +
              1,
        );
        form.relatedFields.add(newNoteField);
      } else {
        ticketNote.definition = ticketNote.definition.copyWith(isHidden: false);
        ticketNote.definition = ticketNote.definition.copyWith(
            order: (form.relatedFields
                    .map((x) => x.definition.order ?? 0)
                    .fold(0, max)) +
                1);
      }
    } else {
      if (ticketNote != null) {
        ticketNote.definition = ticketNote.definition.copyWith(isHidden: true);
      }
    }
  }
}
