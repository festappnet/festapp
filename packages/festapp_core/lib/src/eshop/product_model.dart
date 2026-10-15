import 'product_price_change.dart';
import 'product_price_wave.dart';
import 'product_inventory_context_model.dart';
import 'package:festapp_core/json_values.dart';

const _unchanged = Object();

class ProductModel {
  final int? id;
  final String? deleteBlockedReason;
  final bool? deletionAllowed;
  final List<ProductPriceChange> priceChanges;
  final List<ProductVisibilityChange> visibilityChanges;
  final DateTime? priceServerTime;
  final Duration priceClockOffset;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? title;
  final bool? isHidden;
  final String? description;
  final double? price;
  final Map<String, dynamic>? data;
  final int? productTypeId;
  final int? occasion;
  final String? productTypeString;
  final String? productTypeTitleString;
  final int? order;
  final int? maximum;
  final int? orderedCount;
  final int? paidCount;
  final int? sentCount;
  final String? currencyCode;
  final List<ProductInventoryContextModel> includedInventories;
  final bool? isDynamicallyAvailable;
  final List<int> formIds;
  final String? formTitles;
  bool get canDelete => id == null || deletionAllowed == true;
  String toBasicString() => title ?? id.toString();
  DateTime priceTime(DateTime localNow) =>
      localNow.toUtc().add(priceClockOffset);

  static const String foodType = "food";
  static const String taxiType = "taxi";
  static const String spotType = "spot";
  static const String metaTypeField = "type";
  static const String metaProductTypeTitleStringField = "type_title";
  static const String metaOrderedCount = "ordered_count";
  static const String metaIsDynamicallyAvailable = "is_dynamically_available";
  static const String metaPaidCount = "paid_count";
  static const String metaSentCount = "sent_count";

  String? get shortTitle => data?['short_title'];
  ProductModel withShortTitle(String? value) {
    final data = <String, dynamic>{...?this.data};
    if (value == null || value.isEmpty) {
      data.remove('short_title');
    } else {
      data['short_title'] = value;
    }
    return copyWith(data: data);
  }

  Map<String, dynamic> get _metaSurchargeMap {
    if (data != null && data!['meta_surcharge'] is Map) {
      return Map<String, dynamic>.from(data!['meta_surcharge']);
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

  ProductModel withMetaSurchargeAmount(double? value) {
    final data = <String, dynamic>{...?this.data};
    if (data['meta_surcharge'] is! Map) {
      data['meta_surcharge'] = {};
    }
    final map = Map<String, dynamic>.from(data['meta_surcharge'] as Map);
    data['meta_surcharge'] = map;
    if (value == null || value == 0) {
      map.remove('amount');
    } else {
      map['amount'] = value;
    }
    if (!map.containsKey('amount')) {
      data.remove('meta_surcharge');
    }
    return copyWith(data: data);
  }

  String? get metaSurchargeCurrency {
    return _metaSurchargeMap['currency']?.toString();
  }

  ProductModel withMetaSurchargeCurrency(String? value) {
    final data = <String, dynamic>{...?this.data};
    if (data['meta_surcharge'] is! Map) {
      data['meta_surcharge'] = {};
    }
    final map = Map<String, dynamic>.from(data['meta_surcharge'] as Map);
    data['meta_surcharge'] = map;
    if (value == null || value.isEmpty) {
      map.remove('currency');
    } else {
      map['currency'] = value;
    }
    if (map.isEmpty || !map.containsKey('amount')) {
      data.remove('meta_surcharge');
    }
    return copyWith(data: data);
  }

  Map<String, dynamic> get _depositMap {
    if (data != null && data!['deposit'] is Map) {
      return Map<String, dynamic>.from(data!['deposit']);
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

  ProductModel withDepositAmount(double? value) {
    final data = <String, dynamic>{...?this.data};
    if (data['deposit'] is! Map) {
      data['deposit'] = {};
    }
    final map = Map<String, dynamic>.from(data['deposit'] as Map);
    data['deposit'] = map;
    if (value == null || value == 0) {
      map.remove('amount');
    } else {
      map['amount'] = value;
    }
    if (!map.containsKey('amount')) {
      data.remove('deposit');
    }
    return copyWith(data: data);
  }

  String? get depositCurrency {
    return _depositMap['currency']?.toString();
  }

  ProductModel withDepositCurrency(String? value) {
    final data = <String, dynamic>{...?this.data};
    if (data['deposit'] is! Map) {
      data['deposit'] = {};
    }
    final map = Map<String, dynamic>.from(data['deposit'] as Map);
    data['deposit'] = map;
    if (value == null || value.isEmpty) {
      map.remove('currency');
    } else {
      map['currency'] = value;
    }

    if (map.isEmpty || !map.containsKey('amount')) {
      data.remove('deposit');
    }
    return copyWith(data: data);
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
    Map<String, dynamic>? data,
    this.productTypeId,
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
  }) : data = data == null
           ? null
           : freezeJsonValue(data) as Map<String, dynamic>,
       priceChanges = List.unmodifiable(priceChanges ?? const []),
       visibilityChanges = List.unmodifiable(visibilityChanges ?? const []),
       includedInventories = List.unmodifiable(includedInventories ?? const []),
       formIds = List.unmodifiable(formIds ?? const []);

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>();

    return ProductModel(
      visibilityChanges: (json['visibility_changes'] as List? ?? [])
          .map((c) => ProductVisibilityChange.fromJson(c))
          .toList(),
      priceChanges: (json['price_changes'] as List? ?? [])
          .map((c) => ProductPriceChange.fromJson(c))
          .toList(),
      id: json['id'],
      deleteBlockedReason: json['delete_blocked_reason'],
      deletionAllowed: json['can_delete'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      title: json['title'],
      isHidden: json['is_hidden'],
      description: json['description'],
      price: json['price'] != null
          ? double.tryParse(json['price'].toString())
          : null,
      currencyCode: json['currency_code'],
      data: data,
      productTypeId: json['product_type'],
      occasion: json['occasion'],
      productTypeString: json[metaTypeField],
      productTypeTitleString: json[metaProductTypeTitleStringField],
      order: json['order'],
      maximum: json['maximum'],
      orderedCount: json[metaOrderedCount],
      paidCount: json[metaPaidCount],
      sentCount: json[metaSentCount],
      isDynamicallyAvailable: json[metaIsDynamicallyAvailable],
      formIds: List<int>.from(json['form_ids'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'is_hidden': isHidden,
    'description': description,
    'price': price,
    'currency_code': currencyCode,
    'data': data,
    'product_type': productTypeId,
    'occasion': occasion,
    'order': order,
    'maximum': maximum,
  };

  ProductModel copyWith({
    Object? id = _unchanged,
    Object? deleteBlockedReason = _unchanged,
    Object? deletionAllowed = _unchanged,
    Object? priceChanges = _unchanged,
    Object? visibilityChanges = _unchanged,
    Object? priceServerTime = _unchanged,
    Object? priceClockOffset = _unchanged,
    Object? createdAt = _unchanged,
    Object? updatedAt = _unchanged,
    Object? title = _unchanged,
    Object? isHidden = _unchanged,
    Object? description = _unchanged,
    Object? price = _unchanged,
    Object? data = _unchanged,
    Object? productTypeId = _unchanged,
    Object? occasion = _unchanged,
    Object? productTypeString = _unchanged,
    Object? productTypeTitleString = _unchanged,
    Object? order = _unchanged,
    Object? maximum = _unchanged,
    Object? orderedCount = _unchanged,
    Object? paidCount = _unchanged,
    Object? sentCount = _unchanged,
    Object? currencyCode = _unchanged,
    Object? includedInventories = _unchanged,
    Object? isDynamicallyAvailable = _unchanged,
    Object? formIds = _unchanged,
    Object? formTitles = _unchanged,
  }) => ProductModel(
    id: identical(id, _unchanged) ? this.id : id as int?,
    deleteBlockedReason: identical(deleteBlockedReason, _unchanged)
        ? this.deleteBlockedReason
        : deleteBlockedReason as String?,
    deletionAllowed: identical(deletionAllowed, _unchanged)
        ? this.deletionAllowed
        : deletionAllowed as bool?,
    priceChanges: identical(priceChanges, _unchanged)
        ? this.priceChanges
        : priceChanges as List<ProductPriceChange>,
    visibilityChanges: identical(visibilityChanges, _unchanged)
        ? this.visibilityChanges
        : visibilityChanges as List<ProductVisibilityChange>,
    priceServerTime: identical(priceServerTime, _unchanged)
        ? this.priceServerTime
        : priceServerTime as DateTime?,
    priceClockOffset: identical(priceClockOffset, _unchanged)
        ? this.priceClockOffset
        : priceClockOffset as Duration,
    createdAt: identical(createdAt, _unchanged)
        ? this.createdAt
        : createdAt as DateTime?,
    updatedAt: identical(updatedAt, _unchanged)
        ? this.updatedAt
        : updatedAt as DateTime?,
    title: identical(title, _unchanged) ? this.title : title as String?,
    isHidden: identical(isHidden, _unchanged)
        ? this.isHidden
        : isHidden as bool?,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    price: identical(price, _unchanged)
        ? this.price
        : (price as num?)?.toDouble(),
    data: identical(data, _unchanged)
        ? this.data
        : (data as Map?)?.cast<String, dynamic>(),
    productTypeId: identical(productTypeId, _unchanged)
        ? this.productTypeId
        : productTypeId as int?,
    occasion: identical(occasion, _unchanged)
        ? this.occasion
        : occasion as int?,
    productTypeString: identical(productTypeString, _unchanged)
        ? this.productTypeString
        : productTypeString as String?,
    productTypeTitleString: identical(productTypeTitleString, _unchanged)
        ? this.productTypeTitleString
        : productTypeTitleString as String?,
    order: identical(order, _unchanged) ? this.order : order as int?,
    maximum: identical(maximum, _unchanged) ? this.maximum : maximum as int?,
    orderedCount: identical(orderedCount, _unchanged)
        ? this.orderedCount
        : orderedCount as int?,
    paidCount: identical(paidCount, _unchanged)
        ? this.paidCount
        : paidCount as int?,
    sentCount: identical(sentCount, _unchanged)
        ? this.sentCount
        : sentCount as int?,
    currencyCode: identical(currencyCode, _unchanged)
        ? this.currencyCode
        : currencyCode as String?,
    includedInventories: identical(includedInventories, _unchanged)
        ? this.includedInventories
        : includedInventories as List<ProductInventoryContextModel>,
    isDynamicallyAvailable: identical(isDynamicallyAvailable, _unchanged)
        ? this.isDynamicallyAvailable
        : isDynamicallyAvailable as bool?,
    formIds: identical(formIds, _unchanged)
        ? this.formIds
        : formIds as List<int>,
    formTitles: identical(formTitles, _unchanged)
        ? this.formTitles
        : formTitles as String?,
  );

  /// Returns true if the product has capacity and is dynamically available.
  /// It checks static limits (`maximum` vs `orderedCount`) and the dynamic availability flag from the backend.
  /// If `isDynamicallyAvailable` is null, it's treated as true to ensure backward compatibility.
  bool get isAvailable =>
      ((maximum == null || maximum == 0) ||
          ((orderedCount ?? 0) < (maximum ?? 0))) &&
      (isDynamicallyAvailable ?? true);

  String getFormattedProductTitle() {
    if (price != null) {
      final priceString = "${price!.toStringAsFixed(2)} ${currencyCode ?? ''}"
          .trim();
      return "$title ($priceString)";
    }
    return title ?? "";
  }
}
