import 'package:fstapp/components/eshop/order_amount_change.dart';

/// The exact seat assignments and financial effects approved by an operator.
/// Prices are authoritative decimal strings from the shared SQL owner.
class BlueprintSeatSwapPreview {
  BlueprintSeatSwapPreview._({
    required this.organizationId,
    required this.unitId,
    required this.occasionId,
    required this.blueprintId,
    required this.layoutRevision,
    required this.firstSpotId,
    required this.secondSpotId,
    required List<int> sourceSpotIds,
    required List<int> targetSpotIds,
    required this.confirmationHash,
    required List<BlueprintSwapSeat> seats,
    required List<OrderAmountChange> orders,
  })  : sourceSpotIds = List.unmodifiable(sourceSpotIds),
        targetSpotIds = List.unmodifiable(targetSpotIds),
        sourceIds = Set.unmodifiable(sourceSpotIds),
        seats = List.unmodifiable(seats),
        orders = List.unmodifiable(orders);

  final int organizationId, occasionId, blueprintId, layoutRevision;
  final int firstSpotId, secondSpotId;
  final int? unitId;
  final List<int> sourceSpotIds, targetSpotIds;
  final Set<int> sourceIds;
  final String confirmationHash;
  final List<BlueprintSwapSeat> seats;
  final List<OrderAmountChange> orders;

  factory BlueprintSeatSwapPreview.fromJson(Map<String, dynamic> json,
      {required int organizationId, int? unitId}) {
    final source = (json['sourceSpotIds'] as List).cast<int>();
    final target = (json['targetSpotIds'] as List).cast<int>();
    final all = {...source, ...target};
    final seats = (json['seats'] as List)
        .map((row) =>
            BlueprintSwapSeat.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    final orders = (json['orders'] as List)
        .map((row) =>
            OrderAmountChange.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    final affectedOrders = seats.map((s) => s.orderId).whereType<int>().toSet();
    final hash = json['confirmationHash'] as String;
    if ((json['layoutRevision'] as int) < 0 ||
        source.isEmpty ||
        target.isEmpty ||
        all.length > 20000 ||
        all.length != source.length + target.length ||
        all.any((id) => id <= 0) ||
        !source.contains(json['firstSpotId']) ||
        !target.contains(json['secondSpotId']) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        seats.length != all.length ||
        seats.map((s) => s.id).toSet().length != all.length ||
        seats.any((s) => !all.contains(s.id)) ||
        orders.length != affectedOrders.length ||
        orders.map((o) => o.orderId).toSet().length != affectedOrders.length ||
        orders.any((o) => !affectedOrders.contains(o.orderId))) {
      throw const FormatException('Incomplete seat swap confirmation');
    }
    return BlueprintSeatSwapPreview._(
      organizationId: organizationId,
      unitId: unitId,
      occasionId: json['occasionId'] as int,
      blueprintId: json['blueprintId'] as int,
      layoutRevision: json['layoutRevision'] as int,
      firstSpotId: json['firstSpotId'] as int,
      secondSpotId: json['secondSpotId'] as int,
      sourceSpotIds: source,
      targetSpotIds: target,
      confirmationHash: hash,
      seats: seats,
      orders: orders,
    );
  }
}

class BlueprintSwapSeat {
  const BlueprintSwapSeat(
      {required this.id,
      required this.state,
      this.title,
      this.productId,
      this.productTitle,
      this.orderId,
      this.ticketId,
      this.customerName,
      this.customerSurname,
      this.customerEmail});
  final int id;
  final int? productId, orderId, ticketId;
  final String state;
  final String? title,
      productTitle,
      customerName,
      customerSurname,
      customerEmail;

  factory BlueprintSwapSeat.fromJson(Map<String, dynamic> json) {
    final state = json['state'] as String;
    if (!const {'available', 'selected', 'ordered', 'used'}.contains(state)) {
      throw const FormatException('Invalid seat lifecycle');
    }
    final customer = json['customer'] as Map?;
    return BlueprintSwapSeat(
        id: json['spotId'] as int,
        state: state,
        title: json['title'] as String?,
        productId: json['productId'] as int?,
        productTitle: json['productTitle'] as String?,
        orderId: json['orderId'] as int?,
        ticketId: json['ticketId'] as int?,
        customerName: customer?['name'] as String?,
        customerSurname: customer?['surname'] as String?,
        customerEmail: customer?['email'] as String?);
  }
}
