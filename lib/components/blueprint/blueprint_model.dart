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

  int? id;
  int aggregateVersion;
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
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
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
      objects: enrichedObjects ?? [],
      groups: groups,
      backgroundSvg: json[TbEshop.blueprints.background_svg],
      products: products,
      tickets: tickets,
      orders: orders,
      orderProductTickets: orderProductTickets,
    );
  }

  Map<String, dynamic> toJson() => {
        TbEshop.blueprints.id: id,
        TbEshop.blueprints.created_at: createdAt?.toIso8601String(),
        TbEshop.blueprints.data: data,
        TbEshop.blueprints.title: title,
        TbEshop.blueprints.occasion: occasion,
        TbEshop.blueprints.organization: organization,
        TbEshop.blueprints.configuration: configuration,
        TbEshop.blueprints.objects: objects,
        TbEshop.blueprints.groups: groups,
        TbEshop.blueprints.background_svg: backgroundSvg,
        TbEshop.products.table: products,
        TbEshop.tickets.table: tickets,
        TbEshop.orders.table: orders,
        TbEshop.order_product_ticket.table: orderProductTickets,
      };

  /// Authoring never submits the read bundle's orders, tickets or occupancy.
  Map<String, dynamic> toSaveJson() => {
        'id': id,
        'occasion': occasion,
        'organization': organization,
        'expected_aggregate_version': aggregateVersion,
        'title': title,
        'data': data,
        'configuration': configuration?.toJson(),
        'groups': groups?.map((g) => g.toJson()).toList(),
        'background_svg': backgroundSvg,
        'objects':
            objects?.map((o) => o.toJson()..remove('state')).toList() ?? [],
      };

  String toBasicString() => title ?? id.toString();

  BlueprintModel({
    this.id,
    this.aggregateVersion = 0,
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
    for (var o in objects ?? []) {
      o.blueprint = this;
    }
  }

  int getFirstAvailableGroupId() {
    int id = 1;
    while (groups?.any((group) => group.id == id) ?? false) {
      id++;
    }
    return id;
  }
}
