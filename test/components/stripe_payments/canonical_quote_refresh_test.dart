import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/forms/payment_quote_refresh.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  for (final price in [123.45, 0.0]) {
    test('payment review uses canonical held seats and fresh price $price without legacy objects', () {
      final blueprint = BlueprintModel.fromJson({
        'id': 1, 'occasion': 1,
        'layout': VenueLayoutDocument(nodes: const []).toJson(),
        'objects': 'invalid archival representation',
        'seatBindings': [
          for (final id in [11, 12, 13])
            {'nodeId': 'seat$id', 'spotId': id, 'productId': 7, 'title': 'Seat $id'},
        ],
        'spots': [
          {'id': 11, 'state': 'selected_by_me', 'product': 7},
          {'id': 12, 'state': 'ordered', 'product': 7},
          {'id': 13, 'state': 'selected_by_me', 'product': 7},
        ],
        'products': [{'id': 7, 'title': 'Admission', 'price': price, 'currency_code': 'CZK'}],
      });
      expect(blueprint.objects, isNull);
      final seats = refreshedReservedPaymentSeats(blueprint, [11, 12]);
      expect(seats.keys, [11]);
      expect(seats[11]!.seat!.product!.price, price);
      expect(seats[11]!.seat!.product!.currencyCode, 'CZK');
    });
  }
}
