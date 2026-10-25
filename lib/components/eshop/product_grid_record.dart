import 'package:festapp_core/eshop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:trina_grid/trina_grid.dart';

typedef ProductGridGuard = Future<bool> Function(
  BuildContext context, {
  required Future<void> Function() futureFunction,
  String? defaultErrorMessage,
  bool rethrowError,
  bool showAsDialog,
});

/// Application grid adapter. Editable values live in Trina cells; this record
/// retains the loaded snapshot and the explicit command scope, without a second
/// mutable copy of domain fields.
class ProductGridRecord extends ITrinaRowModel {
  ProductGridRecord(
      {required this.product,
      required this.commands,
      required this.guard,
      this.productTypeTitle});
  ProductModel product;
  final EshopCommands commands;
  final ProductGridGuard guard;
  final String? productTypeTitle;
  @override
  int? get id => product.id;
  @override
  String toBasicString() => product.toBasicString();

  static ProductGridRecord fromPlutoJson(
    Map<String, dynamic> json, {
    required EshopCommands commands,
    required ProductGridGuard guard,
    String? productTypeTitle,
  }) {
    final record =
        json[EshopColumnIds.PRODUCT_MODEL_REFERENCE] as ProductGridRecord?;
    final model = record?.product;
    Map<String, dynamic>? data;
    if (model?.data != null) {
      data = Map.from(model!.data!);
    }
    if (json.containsKey(EshopColumnIds.PRODUCT_SHORT_TITLE)) {
      data ??= {};
      var val = json[EshopColumnIds.PRODUCT_SHORT_TITLE];
      if (val != null && val.toString().isNotEmpty) {
        data[TbEshop.products.data_short_title] = val.toString();
      } else {
        data.remove(TbEshop.products.data_short_title);
      }
    }
    if (json.containsKey(EshopColumnIds.PRODUCT_DEPOSIT)) {
      data ??= {};
      var val = json[EshopColumnIds.PRODUCT_DEPOSIT];
      var parsed = val != null ? double.tryParse(val.toString()) : null;
      if (parsed != null && parsed > 0) {
        var depositMap = data[TbEshop.products.data_deposit];
        if (depositMap is! Map) depositMap = {};
        depositMap = Map<String, dynamic>.from(depositMap);
        depositMap['amount'] = parsed;
        data[TbEshop.products.data_deposit] = depositMap;
      } else {
        if (data[TbEshop.products.data_deposit] is Map) {
          var depositMap =
              Map<String, dynamic>.from(data[TbEshop.products.data_deposit]);
          depositMap.remove('amount');
          if (depositMap.isEmpty) {
            data.remove(TbEshop.products.data_deposit);
          } else {
            data[TbEshop.products.data_deposit] = depositMap;
          }
        }
      }
    }
    if (json.containsKey(EshopColumnIds.PRODUCT_SURCHARGE)) {
      data ??= {};
      var val = json[EshopColumnIds.PRODUCT_SURCHARGE];
      var parsed = val != null ? double.tryParse(val.toString()) : null;
      // Negative is allowed (slevy) — only 0/null clears the value.
      if (parsed != null && parsed != 0) {
        var msMap = data[TbEshop.products.data_meta_surcharge];
        if (msMap is! Map) msMap = {};
        msMap = Map<String, dynamic>.from(msMap);
        msMap['amount'] = parsed;
        data[TbEshop.products.data_meta_surcharge] = msMap;
      } else {
        if (data[TbEshop.products.data_meta_surcharge] is Map) {
          var msMap = Map<String, dynamic>.from(
              data[TbEshop.products.data_meta_surcharge]);
          msMap.remove('amount');
          if (msMap.isEmpty) {
            data.remove(TbEshop.products.data_meta_surcharge);
          } else {
            data[TbEshop.products.data_meta_surcharge] = msMap;
          }
        }
      }
    }
    if (json.containsKey(EshopColumnIds.PRODUCT_SURCHARGE_CURRENCY)) {
      data ??= {};
      var val = json[EshopColumnIds.PRODUCT_SURCHARGE_CURRENCY];
      // Normalize: trim + uppercase ISO code. Cap at 3 chars defensively.
      final raw = val?.toString().trim().toUpperCase() ?? '';
      final curr = raw.length > 3 ? raw.substring(0, 3) : raw;
      if (curr.isNotEmpty) {
        var msMap = data[TbEshop.products.data_meta_surcharge];
        if (msMap is! Map) msMap = {};
        msMap = Map<String, dynamic>.from(msMap);
        msMap['currency'] = curr;
        // Only persist if there's an amount alongside — currency without amount is meaningless.
        if (msMap.containsKey('amount')) {
          data[TbEshop.products.data_meta_surcharge] = msMap;
        }
      } else {
        if (data[TbEshop.products.data_meta_surcharge] is Map) {
          var msMap = Map<String, dynamic>.from(
              data[TbEshop.products.data_meta_surcharge]);
          msMap.remove('currency');
          if (msMap.isEmpty) {
            data.remove(TbEshop.products.data_meta_surcharge);
          } else {
            data[TbEshop.products.data_meta_surcharge] = msMap;
          }
        }
      }
    }

    return ProductGridRecord(
        commands: commands,
        guard: guard,
        productTypeTitle: productTypeTitle ?? record?.productTypeTitle,
        product: ProductModel(
          aggregateVersion: model?.aggregateVersion ?? 0,
          id: json[EshopColumnIds.PRODUCT_ID] == -1
              ? null
              : json[EshopColumnIds.PRODUCT_ID],
          title: json[EshopColumnIds.PRODUCT_TITLE],
          isHidden: json[EshopColumnIds.PRODUCT_IS_HIDDEN] == 'true',
          data: data,
          description: json[EshopColumnIds.PRODUCT_DESCRIPTION],
          price: json[EshopColumnIds.PRODUCT_PRICE] != null
              ? double.tryParse(json[EshopColumnIds.PRODUCT_PRICE].toString())
              : null,
          currencyCode: json[EshopColumnIds.PRODUCT_CURRENCY_CODE],
          order: json[EshopColumnIds.PRODUCT_ORDER],
          maximum: json[EshopColumnIds.PRODUCT_MAXIMUM],
          orderedCount: model?.orderedCount,
          purchasedCount: model?.purchasedCount,
          paidCount: model?.paidCount,
          sentCount: model?.sentCount,
          priceChanges: model?.priceChanges,
          visibilityChanges: model?.visibilityChanges,
          priceServerTime: model?.priceServerTime,
          priceClockOffset: model?.priceClockOffset ?? Duration.zero,
          includedInventories:
              (json[EshopColumnIds.PRODUCT_INCLUDED_INVENTORY] as List?)
                      ?.cast<ProductInventoryContextModel>() ??
                  model?.includedInventories ??
                  [],
          formIds: model?.formIds ?? [],
          formTitles: model?.formTitles,
        ));
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    final product = this.product;
    final total = product.purchasedCount ?? 0;
    return TrinaRow(cells: {
      EshopColumnIds.PRODUCT_ID: TrinaCell(value: product.id ?? 0),
      EshopColumnIds.PRODUCT_IS_HIDDEN:
          TrinaCell(value: product.isHidden.toString()),
      EshopColumnIds.PRODUCT_TITLE: TrinaCell(value: product.title ?? ''),
      EshopColumnIds.PRODUCT_SHORT_TITLE:
          TrinaCell(value: product.shortTitle ?? ''),
      EshopColumnIds.PRODUCT_DESCRIPTION:
          TrinaCell(value: product.description ?? ''),
      EshopColumnIds.PRODUCT_PRICE_CHANGES: TrinaCell(value: product),
      EshopColumnIds.PRODUCT_PRICE: TrinaCell(
        value: product.price != null ? product.price?.toStringAsFixed(2) : '',
      ),
      EshopColumnIds.PRODUCT_CURRENCY_CODE:
          TrinaCell(value: product.currencyCode ?? ''),
      EshopColumnIds.PRODUCT_TYPE: TrinaCell(value: productTypeTitle ?? ''),
      EshopColumnIds.PRODUCT_ORDER: TrinaCell(value: product.order ?? 0),
      EshopColumnIds.PRODUCT_MAXIMUM: TrinaCell(value: product.maximum ?? 0),
      EshopColumnIds.PRODUCT_ORDERED_COUNT:
          TrinaCell(value: product.orderedCount),
      EshopColumnIds.PRODUCT_PAID_COUNT: TrinaCell(value: total),
      EshopColumnIds.PRODUCT_INCLUDED_INVENTORY:
          TrinaCell(value: product.includedInventories),
      EshopColumnIds.PRODUCT_DEPOSIT: TrinaCell(
        value: product.depositAmount != null
            ? product.depositAmount?.toStringAsFixed(2)
            : '',
      ),
      EshopColumnIds.PRODUCT_SURCHARGE: TrinaCell(
        value: product.metaSurchargeAmount != null
            ? product.metaSurchargeAmount?.toStringAsFixed(2)
            : '',
      ),
      EshopColumnIds.PRODUCT_SURCHARGE_CURRENCY: TrinaCell(
        value: product.metaSurchargeCurrency ?? '',
      ),
      EshopColumnIds.PRODUCT_USED_IN_FORMS:
          TrinaCell(value: product.formTitles ?? ''),
      EshopColumnIds.PRODUCT_MODEL_REFERENCE: TrinaCell(value: this),
    });
  }

  @override
  Future<void> updateMethod(BuildContext context) =>
      guard(context, futureFunction: () async {
        final saved = await commands.saveProduct({
          ...product.toJson(),
          if (product.id != null)
            'expected_aggregate_version': product.aggregateVersion,
          'inventory_contexts': product.includedInventories
              .map((link) => {
                    'inventory_context_id': link.inventoryContextId,
                    'quantity': link.quantity,
                  })
              .toList(),
        });
        product = product.copyWith(
            id: saved.id, aggregateVersion: saved.aggregateVersion);
      },
          defaultErrorMessage: OrdersStrings.failedToSaveProduct,
          rethrowError: true);

  @override
  Future<void> deleteMethod(BuildContext context) async {
    if (id == null) return;
    await guard(context,
        futureFunction: () => commands.deleteProduct(id!,
            expectedVersion: product.aggregateVersion),
        defaultErrorMessage: OrdersStrings.failedToDeleteProduct,
        rethrowError: true);
  }
}

abstract final class ProductPresentation {
  static String typeToLocale(String type) => switch (type) {
        ProductModel.foodType => CommonStrings.food,
        ProductModel.spotType => CommonStrings.spot,
        _ => CommonStrings.products,
      };
}
