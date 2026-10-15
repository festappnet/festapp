import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';

void main() {
  test('blueprint editor consumes canonical order metadata from its own RPC projection', () {
    final data = <String, dynamic>{
      'id': 1,
      'objects': <dynamic>[],
      'orders': [
        {'id': 17, 'order_sequence': 2, 'order_symbol': '1W8E5J7M2V', 'state': 'paid', 'data': <String, dynamic>{}},
      ],
    };
    final blueprint = BlueprintModel.fromJson(data);
    expect(blueprint.orders!.single.id, 17);
    expect(blueprint.orders!.single.orderSequence, 2);
    expect(blueprint.orders!.single.orderSymbol, '1W8E5J7M2V');
    // The pre-fix projection returned neither field and failed this exact caller.
    final oldOrder = Map<String, dynamic>.from((data['orders'] as List).single)
      ..remove('order_sequence') ..remove('order_symbol');
    expect(() => BlueprintModel.fromJson({...data, 'orders': [oldOrder]}), throwsStateError);
  });
}
