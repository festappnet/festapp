import 'package:collection/collection.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';

/// Extract a value from the dynamic fields stored in [order.data['fields']].
String? getFieldValue(OrderModel order, String targetFieldId) {
  if (order.data == null || order.data!['fields'] == null) {
    return null;
  }
  var fieldsList = order.data!['fields'];
  if (fieldsList is! List) return null;

  for (var fieldEntry in fieldsList) {
    if (fieldEntry is Map) {
      for (var key in fieldEntry.keys) {
        if (key.toString() == targetFieldId) {
          var value = fieldEntry[key];
          return (value != null && value.toString().isNotEmpty)
              ? value.toString()
              : null;
        }
      }
    }
  }
  return null;
}

/// Get the total price for a specific ticket from [order.data['tickets']].
double? getTicketPrice(TicketModel? scannedObject) {
  if (scannedObject == null ||
      scannedObject.relatedOrder == null ||
      scannedObject.relatedOrder!.data == null) {
    return null;
  }

  final data = scannedObject.relatedOrder!.data!;

  if (data.containsKey('tickets') && data['tickets'] is List) {
    final ticketsList = data['tickets'] as List;

    final ticketData = ticketsList
        .firstWhereOrNull((t) => t is Map && t['id'] == scannedObject.id);

    if (ticketData != null && ticketData is Map) {
      double totalTicketPrice = 0.0;
      bool productsFound = false;

      if (ticketData.containsKey('products') &&
          ticketData['products'] is List) {
        final productsList = ticketData['products'] as List;

        for (var product in productsList) {
          if (product is Map && product.containsKey('price')) {
            productsFound = true;
            totalTicketPrice +=
                double.tryParse(product['price'].toString()) ?? 0.0;
          }
        }
      }

      if (productsFound ||
          (ticketData.containsKey('products') &&
              (ticketData['products'] as List).isEmpty)) {
        return totalTicketPrice;
      }
    }
  }
  return null;
}
