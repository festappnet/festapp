import 'product_price_wave.dart';
import 'package:fstapp/services/time_helper.dart';
import 'product_price_change.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/inventory/models/product_inventory_context_model.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:trina_grid/trina_grid.dart';

import '../eshop_columns.dart';

class ProductModel extends ITrinaRowModel {
  @override
  int? id;
  String? deleteBlockedReason;
  bool? deletionAllowed;
  bool get canDelete => id == null || deletionAllowed == true;
  List<ProductPriceChange> priceChanges = [];
  List<ProductVisibilityChange> visibilityChanges = [];
  DateTime? priceServerTime;
  Duration priceClockOffset = Duration.zero;
  DateTime get priceNow =>
      (TimeHelper.currentTime ?? DateTime.now()).toUtc().add(priceClockOffset);
  DateTime? createdAt;
  DateTime? updatedAt;
  String? title;
  bool? isHidden;
  String? description;
  double? price;
  Map<String, dynamic>? data;
  int? productTypeId;
  ProductTypeModel? productType;
  int? occasion;
  String? productTypeString;
  String? productTypeTitleString;
  int? order;
  int? maximum;
  int? orderedCount;
  int? paidCount;
  int? sentCount;
  String? currencyCode;
  List<ProductInventoryContextModel> includedInventories = [];
  bool? isDynamicallyAvailable;
  List<int> formIds;
  String? formTitles;

  static const String foodType = "food";
  static const String taxiType = "taxi";
  static const String spotType = "spot";
  static const String metaTypeField = "type";
  static const String metaProductTypeTitleStringField = "type_title";
  static const String metaOrderedCount = "ordered_count";
  static const String metaIsDynamicallyAvailable = "is_dynamically_available";
  static const String metaPaidCount = "paid_count";
  static const String metaSentCount = "sent_count";

  String? get shortTitle => data?[TbEshop.products.data_short_title];
  set shortTitle(String? value) {
    data ??= {};
    if (value == null || value.isEmpty) {
      data!.remove(TbEshop.products.data_short_title);
    } else {
      data![TbEshop.products.data_short_title] = value;
    }
  }

  Map<String, dynamic> get _metaSurchargeMap {
    if (data != null && data![TbEshop.products.data_meta_surcharge] is Map) {
      return Map<String, dynamic>.from(
          data![TbEshop.products.data_meta_surcharge]);
    }
    return {};
  }

  double? get metaSurchargeAmount {
    var val = _metaSurchargeMap['amount'];
    double? result;
    if (val is num) result = val.toDouble();
    if (val is String) result = double.tryParse(val);
    if (result == 0) return null;
    return result;
  }

  set metaSurchargeAmount(double? value) {
    data ??= {};
    if (data![TbEshop.products.data_meta_surcharge] is! Map) {
      data![TbEshop.products.data_meta_surcharge] = {};
    }
    var map = data![TbEshop.products.data_meta_surcharge] as Map;
    if (value == null || value == 0) {
      map.remove('amount');
    } else {
      map['amount'] = value;
    }
    if (!map.containsKey('amount')) {
      data!.remove(TbEshop.products.data_meta_surcharge);
    }
  }

  String? get metaSurchargeCurrency {
    return _metaSurchargeMap['currency']?.toString();
  }

  set metaSurchargeCurrency(String? value) {
    data ??= {};
    if (data![TbEshop.products.data_meta_surcharge] is! Map) {
      data![TbEshop.products.data_meta_surcharge] = {};
    }
    var map = data![TbEshop.products.data_meta_surcharge] as Map;
    if (value == null || value.isEmpty) {
      map.remove('currency');
    } else {
      map['currency'] = value;
    }
    if (map.isEmpty || !map.containsKey('amount')) {
      data!.remove(TbEshop.products.data_meta_surcharge);
    }
  }

  Map<String, dynamic> get _depositMap {
    if (data != null && data![TbEshop.products.data_deposit] is Map) {
      return Map<String, dynamic>.from(data![TbEshop.products.data_deposit]);
    }
    return {};
  }

  double? get depositAmount {
    var val = _depositMap['amount'];
    double? result;
    if (val is num) result = val.toDouble();
    if (val is String) result = double.tryParse(val);
    if (result == 0) return null;
    return result;
  }

  set depositAmount(double? value) {
    data ??= {};
    if (data![TbEshop.products.data_deposit] is! Map) {
      data![TbEshop.products.data_deposit] = {};
    }
    var map = data![TbEshop.products.data_deposit] as Map;
    if (value == null || value == 0) {
      map.remove('amount');
    } else {
      map['amount'] = value;
    }
    if (!map.containsKey('amount')) {
      data!.remove(TbEshop.products.data_deposit);
    }
  }

  String? get depositCurrency {
    return _depositMap['currency']?.toString();
  }

  set depositCurrency(String? value) {
    data ??= {};
    if (data![TbEshop.products.data_deposit] is! Map) {
      data![TbEshop.products.data_deposit] = {};
    }
    var map = data![TbEshop.products.data_deposit] as Map;
    if (value == null || value.isEmpty) {
      map.remove('currency');
    } else {
      map['currency'] = value;
    }

    if (map.isEmpty || !map.containsKey('amount')) {
      data!.remove(TbEshop.products.data_deposit);
    }
  }

  ProductModel({
    this.id,
    this.deleteBlockedReason,
    this.deletionAllowed,
    List<ProductPriceChange>? priceChanges,
    List<ProductVisibilityChange>? visibilityChanges,
    this.priceServerTime,
    this.priceClockOffset = Duration.zero,
    this.createdAt,
    this.updatedAt,
    this.title,
    this.isHidden,
    this.description,
    this.price,
    this.data,
    this.productTypeId,
    this.productType,
    this.occasion,
    this.productTypeString,
    this.productTypeTitleString,
    this.order,
    this.maximum,
    this.orderedCount,
    this.paidCount,
    this.sentCount,
    this.currencyCode,
    List<ProductInventoryContextModel>? includedInventories,
    this.isDynamicallyAvailable,
    List<int>? formIds,
    this.formTitles,
  })  : visibilityChanges = visibilityChanges ?? [],
        priceChanges = priceChanges ?? [],
        includedInventories = includedInventories ?? [],
        formIds = formIds ?? [];

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? data = json[TbEshop.products.data];

    return ProductModel(
      visibilityChanges: (json['visibility_changes'] as List? ?? [])
          .map((c) => ProductVisibilityChange.fromJson(c))
          .toList(),
      priceChanges: (json['price_changes'] as List? ?? [])
          .map((c) => ProductPriceChange.fromJson(c))
          .toList(),
      id: json[TbEshop.products.id],
      deleteBlockedReason: json['delete_blocked_reason'],
      deletionAllowed: json['can_delete'],
      createdAt: json[TbEshop.products.created_at] != null
          ? DateTime.parse(json[TbEshop.products.created_at])
          : null,
      updatedAt: json[TbEshop.products.updated_at] != null
          ? DateTime.parse(json[TbEshop.products.updated_at])
          : null,
      title: json[TbEshop.products.title],
      isHidden: json[TbEshop.products.is_hidden],
      description: json[TbEshop.products.description],
      price: json[TbEshop.products.price] != null
          ? double.tryParse(json[TbEshop.products.price].toString())
          : null,
      currencyCode: json[TbEshop.products.currency_code],
      data: data,
      productTypeId: json[TbEshop.products.product_type],
      occasion: json[TbEshop.products.occasion],
      productTypeString: json[metaTypeField],
      productTypeTitleString: json[metaProductTypeTitleStringField],
      order: json[TbEshop.products.order],
      maximum: json[TbEshop.products.maximum],
      orderedCount: json[metaOrderedCount],
      paidCount: json[metaPaidCount],
      sentCount: json[metaSentCount],
      isDynamicallyAvailable: json[metaIsDynamicallyAvailable],
      formIds: List<int>.from(json['form_ids'] ?? []),
    );
  }

  static ProductModel fromPlutoJson(Map<String, dynamic> json) {
    var model = json[EshopColumns.PRODUCT_MODEL_REFERENCE] as ProductModel?;
    Map<String, dynamic>? data;
    if (model?.data != null) {
      data = Map.from(model!.data!);
    }
    if (json.containsKey(EshopColumns.PRODUCT_SHORT_TITLE)) {
      data ??= {};
      var val = json[EshopColumns.PRODUCT_SHORT_TITLE];
      if (val != null && val.toString().isNotEmpty) {
        data[TbEshop.products.data_short_title] = val.toString();
      } else {
        data.remove(TbEshop.products.data_short_title);
      }
    }
    if (json.containsKey(EshopColumns.PRODUCT_DEPOSIT)) {
      data ??= {};
      var val = json[EshopColumns.PRODUCT_DEPOSIT];
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
    if (json.containsKey(EshopColumns.PRODUCT_SURCHARGE)) {
      data ??= {};
      var val = json[EshopColumns.PRODUCT_SURCHARGE];
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
    if (json.containsKey(EshopColumns.PRODUCT_SURCHARGE_CURRENCY)) {
      data ??= {};
      var val = json[EshopColumns.PRODUCT_SURCHARGE_CURRENCY];
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

    return ProductModel(
      id: json[EshopColumns.PRODUCT_ID] == -1
          ? null
          : json[EshopColumns.PRODUCT_ID],
      title: json[EshopColumns.PRODUCT_TITLE],
      isHidden: json[EshopColumns.PRODUCT_IS_HIDDEN] == 'true',
      data: data,
      description: json[EshopColumns.PRODUCT_DESCRIPTION],
      price: json[EshopColumns.PRODUCT_PRICE] != null
          ? double.tryParse(json[EshopColumns.PRODUCT_PRICE].toString())
          : null,
      currencyCode: json[EshopColumns.PRODUCT_CURRENCY_CODE],
      order: json[EshopColumns.PRODUCT_ORDER],
      maximum: json[EshopColumns.PRODUCT_MAXIMUM],
      priceChanges: model?.priceChanges,
      visibilityChanges: model?.visibilityChanges,
      priceServerTime: model?.priceServerTime,
      priceClockOffset: model?.priceClockOffset ?? Duration.zero,
      includedInventories: model?.includedInventories ?? [],
      formIds: model?.formIds ?? [],
      formTitles: model?.formTitles,
    );
  }

  Map<String, dynamic> toJson() => {
        TbEshop.products.id: id,
        TbEshop.products.title: title,
        TbEshop.products.is_hidden: isHidden,
        TbEshop.products.description: description,
        TbEshop.products.price: price,
        TbEshop.products.currency_code: currencyCode,
        TbEshop.products.data: data,
        TbEshop.products.product_type: productTypeId,
        TbEshop.products.occasion: occasion,
        TbEshop.products.order: order,
        TbEshop.products.maximum: maximum,
      };

  ProductModel copyWith({
    int? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? title,
    bool? isHidden,
    String? description,
    double? price,
    Map<String, dynamic>? data,
    int? productTypeId,
    ProductTypeModel? productType,
    int? occasion,
    String? productTypeString,
    String? productTypeTitleString,
    int? order,
    int? maximum,
    int? orderedCount,
    int? paidCount,
    int? sentCount,
    String? currencyCode,
    List<ProductInventoryContextModel>? includedInventories,
    bool? isDynamicallyAvailable,
    List<int>? formIds,
    String? formTitles,
  }) {
    return ProductModel(
      priceChanges: priceChanges,
      visibilityChanges: visibilityChanges,
      priceServerTime: priceServerTime,
      priceClockOffset: priceClockOffset,
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: title ?? this.title,
      isHidden: isHidden ?? this.isHidden,
      description: description ?? this.description,
      price: price ?? this.price,
      data: data ??
          (this.data != null ? Map<String, dynamic>.from(this.data!) : null),
      productTypeId: productTypeId ?? this.productTypeId,
      productType: productType ?? this.productType,
      occasion: occasion ?? this.occasion,
      productTypeString: productTypeString ?? this.productTypeString,
      productTypeTitleString:
          productTypeTitleString ?? this.productTypeTitleString,
      order: order ?? this.order,
      maximum: maximum ?? this.maximum,
      orderedCount: orderedCount ?? this.orderedCount,
      paidCount: paidCount ?? this.paidCount,
      sentCount: sentCount ?? this.sentCount,
      currencyCode: currencyCode ?? this.currencyCode,
      includedInventories: includedInventories ?? this.includedInventories,
      isDynamicallyAvailable:
          isDynamicallyAvailable ?? this.isDynamicallyAvailable,
      formIds: formIds ?? this.formIds,
      formTitles: formTitles ?? this.formTitles,
    );
  }

  /// Returns true if the product has capacity and is dynamically available.
  /// It checks static limits (`maximum` vs `orderedCount`) and the dynamic availability flag from the backend.
  /// If `isDynamicallyAvailable` is null, it's treated as true to ensure backward compatibility.
  bool get isAvailable =>
      ((maximum == null || maximum == 0) ||
          ((orderedCount ?? 0) < (maximum ?? 0))) &&
      (isDynamicallyAvailable ?? true);

  @override
  String toBasicString() => title ?? id.toString();

  static String typeToLocale(String type) {
    switch (type) {
      case foodType:
        return CommonStrings.food;
      case spotType:
        return CommonStrings.spot;
      default:
        return CommonStrings.products;
    }
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    final total = (paidCount ?? 0) + (sentCount ?? 0);
    return TrinaRow(cells: {
      EshopColumns.PRODUCT_ID: TrinaCell(value: id ?? 0),
      EshopColumns.PRODUCT_IS_HIDDEN: TrinaCell(value: isHidden.toString()),
      EshopColumns.PRODUCT_TITLE: TrinaCell(value: title ?? ''),
      EshopColumns.PRODUCT_SHORT_TITLE: TrinaCell(value: shortTitle ?? ''),
      EshopColumns.PRODUCT_DESCRIPTION: TrinaCell(value: description ?? ''),
      EshopColumns.PRODUCT_PRICE_CHANGES: TrinaCell(value: this),
      EshopColumns.PRODUCT_PRICE: TrinaCell(
        value: price != null ? price?.toStringAsFixed(2) : '',
      ),
      EshopColumns.PRODUCT_CURRENCY_CODE: TrinaCell(value: currencyCode ?? ''),
      EshopColumns.PRODUCT_TYPE: TrinaCell(value: productType?.title ?? ''),
      EshopColumns.PRODUCT_ORDER: TrinaCell(value: order ?? 0),
      EshopColumns.PRODUCT_MAXIMUM: TrinaCell(value: maximum ?? 0),
      EshopColumns.PRODUCT_ORDERED_COUNT: TrinaCell(value: orderedCount),
      EshopColumns.PRODUCT_PAID_COUNT: TrinaCell(value: total),
      EshopColumns.PRODUCT_INCLUDED_INVENTORY:
          TrinaCell(value: getInventoryDisplayValue(this, context)),
      EshopColumns.PRODUCT_DEPOSIT: TrinaCell(
        value: depositAmount != null ? depositAmount?.toStringAsFixed(2) : '',
      ),
      EshopColumns.PRODUCT_SURCHARGE: TrinaCell(
        value: metaSurchargeAmount != null
            ? metaSurchargeAmount?.toStringAsFixed(2)
            : '',
      ),
      EshopColumns.PRODUCT_SURCHARGE_CURRENCY: TrinaCell(
        value: metaSurchargeCurrency ?? '',
      ),
      EshopColumns.PRODUCT_USED_IN_FORMS: TrinaCell(value: formTitles ?? ''),
      EshopColumns.PRODUCT_MODEL_REFERENCE: TrinaCell(value: this),
    });
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        var productId = await DbEshop.updateProduct(this);
        await DbEshop.updateProductInventoryContexts(
            productId, includedInventories);
      },
      defaultErrorMessage: OrdersStrings.failedToSaveProduct,
      rethrowError: true,
    );
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    if (id == null) return;
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        await DbEshop.deleteProduct(id!);
      },
      defaultErrorMessage: OrdersStrings.failedToDeleteProduct,
      rethrowError: true,
    );
  }

  static String getInventoryDisplayValue(
      ProductModel product, BuildContext context) {
    if (product.includedInventories.isEmpty) {
      return "";
    }
    return product.includedInventories.map((link) {
      final quantityText = link.quantity > 1 ? " (x${link.quantity})" : "";
      // Use the populated object for its title, with a fallback to the ID.
      final title = link.inventoryContext?.getFullTitle(context) ??
          link.inventoryContextId.toString();
      return "$title$quantityText";
    }).join(" | ");
  }

  String getFormattedProductTitle() {
    if (price != null) {
      final priceString =
          "${price!.toStringAsFixed(2)} ${currencyCode ?? ''}".trim();
      return "$title ($priceString)";
    }
    return title ?? "";
  }
}
