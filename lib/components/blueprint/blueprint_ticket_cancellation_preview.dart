import '../eshop/order_amount_change.dart';

class BlueprintTicketCancellationPreview {
  BlueprintTicketCancellationPreview(this.data,
      {required this.organizationId, this.unitId}) {
    if (spotIds.isEmpty ||
        ticketIds.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(data['confirmationHash'] as String)) {
      throw const FormatException('Invalid ticket cancellation preview');
    }
  }
  final Map<String, dynamic> data;
  final int organizationId;
  final int? unitId;
  int get occasionId => data['occasionId'] as int;
  int get blueprintId => data['blueprintId'] as int;
  List<int> get spotIds => (data['requestedSpotIds'] as List).cast<int>();
  List<int> get ticketIds => (data['ticketIds'] as List).cast<int>();
  List<Map<String, dynamic>> get seats => (data['seats'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<OrderAmountChange> get orders => (data['orders'] as List)
      .map((e) =>
          OrderAmountChange.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}
