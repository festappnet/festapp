import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'inventory_pool_model.dart';

class InventoryContextModel {
  int? id;
  int inventoryPoolId;
  DateTime? blockDate;
  String? title;
  int? order;
  InventoryPoolModel? inventoryPool;
  List<SpotModel>? spots;
  int? productId;
  ProductModel? product;

  InventoryContextModel({
    this.id,
    required this.inventoryPoolId,
    this.blockDate,
    this.title,
    this.order,
    this.inventoryPool,
    this.spots,
    this.productId,
    this.product,
  });

  factory InventoryContextModel.fromJson(Map<String, dynamic> json) {
    final t = Tb.inventory_contexts;
    final data = json[t.data] as Map<String, dynamic>? ?? {};

    List<SpotModel>? parsedSpots;
    if (json['spots'] is List) {
      parsedSpots = (json['spots'] as List)
          .map((s) => SpotModel.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return InventoryContextModel(
      id: json[t.id],
      inventoryPoolId: json[t.inventory_pool],
      blockDate: json[t.block_date] != null
          ? DateTime.parse(json[t.block_date])
          : null,
      title: json[t.title],
      order: json[t.order],
      spots: parsedSpots,
      productId: data[t.data_product_id] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final t = Tb.inventory_contexts;
    return {
      t.id: id,
      t.inventory_pool: inventoryPoolId,
      t.block_date: blockDate?.toIso8601String().substring(0, 10), //YYYY-MM-DD
      t.title: title,
      t.order: order,
      t.data: {
        t.data_product_id: product?.id ?? productId,
      }
    };
  }

  /// Creates a JSON representation of the model including the spots.
  Map<String, dynamic> toJsonWithSpots() {
    final data = toJson();
    if (spots != null) {
      data['spots'] = spots!.map((s) => s.toJson()).toList();
    }
    return data;
  }

  /// Creates a new instance with updated fields.
  InventoryContextModel copyWith({
    int? id,
    int? inventoryPoolId,
    DateTime? blockDate,
    String? title,
    int? order,
    InventoryPoolModel? inventoryPool,
    List<SpotModel>? spots,
    int? productId,
    ProductModel? product,
  }) {
    return InventoryContextModel(
      id: id ?? this.id,
      inventoryPoolId: inventoryPoolId ?? this.inventoryPoolId,
      blockDate: blockDate ?? this.blockDate,
      title: title ?? this.title,
      order: order ?? this.order,
      inventoryPool: inventoryPool ?? this.inventoryPool,
      spots: spots ?? this.spots,
      productId: productId ?? this.productId,
      product: product ?? this.product,
    );
  }

  String getContextTitle(BuildContext context) {
    if (title != null && title!.isNotEmpty) {
      return title!;
    }
    if (blockDate != null) {
      final String locale = Localizations.localeOf(context).toString();
      final String datePart = DateFormat.Md(locale).format(blockDate!);
      final String dayOfWeekPart =
          DateFormat('E', locale).format(blockDate!).toUpperCase();
      return '$dayOfWeekPart $datePart';
    }
    return InventoryStrings.contextDefaultTitle;
  }

  String getFullTitle(BuildContext context) =>
      "${inventoryPool?.title ?? InventoryStrings.poolDefaultTitle} - ${getContextTitle(context)}";
}
