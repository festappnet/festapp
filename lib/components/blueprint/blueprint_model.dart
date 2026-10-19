import 'dart:convert';
import 'blueprint_layout_contract.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/get_orders_helper.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'blueprint_configuration.dart';
import 'blueprint_object_model.dart';

class BlueprintModel {
  static const String metaSpots = "spots";
  static const String metaProducts = "products";
  static const String metaTableAreaType = "table";
  static const String metaSpotType = "spot";

  BlueprintLayoutSnapshot? layoutSnapshot;
  Map<String, dynamic> layoutResources;
  Map<String, Map<String, dynamic>> areaAvailability;
  int? id;
  DateTime? createdAt;
  Map<String, dynamic>? data;
  String? title;
  int? organization;
  int? occasion;
  BlueprintConfiguration? configuration;
  List<BlueprintObjectModel>? objects;
  List<BlueprintObjectModel>? spots;
  List<BlueprintGroupModel>? groups;
  String? backgroundSvg;
  List<ProductModel>? products;
  List<TicketModel>? tickets;
  List<OrderModel>? orders;
  List<OrderProductTicketModel>? orderProductTickets;

  /// (New) Helper to get only products of type "spot"
  List<ProductModel> get spotProducts =>
      products
          ?.where((p) => p.productTypeString == ProductModel.spotType)
          .toList() ??
      [];

  factory BlueprintModel.fromJson(Map<String, dynamic> json) {
    if (json['layout'] is! Map) {
      throw StateError('BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    }
    final result = BlueprintModel(
      id: json['id'], occasion: json['occasion'], organization: json['organization'],
      title: json['title'],
      createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at']),
      data: json['data'],
      layoutSnapshot: BlueprintLayoutSnapshot.fromJson(json),
      layoutResources: Map<String, dynamic>.from(jsonDecode(jsonEncode(json['layoutResources'] ?? {})) as Map),
      areaAvailability: {for(final raw in json['areaAvailability'] as List? ?? const [])
        (raw as Map)['nodeId'] as String: Map<String, dynamic>.unmodifiable(raw)},
      spots: GetOrdersHelper.parseSpots(json),
      products: GetOrdersHelper.parseProducts(json),
      tickets: GetOrdersHelper.parseTickets(json),
      orders: GetOrdersHelper.parseOrders(json),
      orderProductTickets: GetOrdersHelper.parseOrderProductTickets(json),
    );
    result.assignAllSpotsWithBlueprint();
    return result;
  }

  /// Explicit input boundary for the offline legacy migration only.
  factory BlueprintModel.fromLegacyJson(Map<String, dynamic> json) {
    final List<BlueprintGroupModel> groups = GetOrdersHelper.parseGroups(json);
    final List<BlueprintObjectModel>? rawObjects =
        GetOrdersHelper.parseObjects(json);
    final List<BlueprintObjectModel>? spots = GetOrdersHelper.parseSpots(json);
    final List<ProductModel>? products = GetOrdersHelper.parseProducts(json);
    final List<TicketModel>? tickets = GetOrdersHelper.parseTickets(json);
    final List<OrderModel>? orders = GetOrdersHelper.parseOrders(json);
    final List<OrderProductTicketModel>? orderProductTickets =
        GetOrdersHelper.parseOrderProductTickets(json);

    final List<BlueprintObjectModel>? enrichedObjects =
        GetOrdersHelper.enrichObjects(rawObjects, spots, products);

    GetOrdersHelper.assignObjectsToGroups(enrichedObjects, groups);

    return BlueprintModel(
      id: json[TbEshop.blueprints.id],
      createdAt: json[TbEshop.blueprints.created_at] != null
          ? DateTime.parse(json[TbEshop.blueprints.created_at])
          : null,
      data: json[TbEshop.blueprints.data],
      title: json[TbEshop.blueprints.title],
      organization: json[TbEshop.blueprints.organization],
      occasion: json[TbEshop.blueprints.occasion],
      configuration: json[TbEshop.blueprints.configuration] != null
          ? BlueprintConfiguration.fromJson(
              json[TbEshop.blueprints.configuration])
          : null,
      areaAvailability: {
        for (final raw in json['areaAvailability'] as List? ?? const [])
          (raw as Map)['nodeId'] as String:
              Map<String, dynamic>.unmodifiable(raw)
      },
      layoutResources: json['layoutResources'] == null
          ? const {}
          : Map<String, dynamic>.from(
              jsonDecode(jsonEncode(json['layoutResources'])) as Map),
      layoutSnapshot: json['layout'] == null
          ? null
          : BlueprintLayoutSnapshot.fromJson(json),
      spots: spots,
      objects: enrichedObjects ?? [],
      groups: groups,
      backgroundSvg: json[TbEshop.blueprints.background_svg],
      products: products,
      tickets: tickets,
      orders: orders,
      orderProductTickets: orderProductTickets,
    );
  }

  Map<String, dynamic> toJson() {
    final snapshot = layoutSnapshot;
    if (snapshot == null) throw StateError('BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    return snapshot.toJson();
  }

  String toBasicString() => title ?? id.toString();

  BlueprintModel({
    this.layoutSnapshot,
    this.layoutResources = const {},
    this.areaAvailability = const {},
    this.id,
    this.createdAt,
    this.data,
    this.title,
    this.organization,
    this.occasion,
    this.configuration,
    this.objects,
    this.spots,
    this.groups,
    this.backgroundSvg,
    this.products,
    this.tickets,
    this.orders,
    this.orderProductTickets,
  });

  void assignAllSpotsWithBlueprint() {
    for (var o in spots ?? []) {
      o.blueprint = this;
    }
  }

}
