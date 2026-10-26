import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_naming.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';

void main() {
  test('group seat lettering preserves existing A Z AA naming', () {
    expect(blueprintSeatTitle('Stůl 1',0),'Stůl 1A');
    expect(blueprintSeatTitle('Stůl 1',25),'Stůl 1Z');
    expect(blueprintSeatTitle('Stůl 1',26),'Stůl 1AA');
    expect(blueprintSeatTitle('Stůl 1',52),'Stůl 1BA');
  });
  test('blueprint editor consumes canonical order metadata from its own RPC projection', () {
    final data = <String, dynamic>{
      'id': 1, 'occasion': 1,
      'layout': VenueLayoutDocument(nodes:const []).toJson(),
      'objects': 'archival-invalid-objects', 'groups': 'archival-invalid-groups',
      'configuration': 'archival-invalid-configuration', 'background_svg': 'archival-background',
      'orders': [
        {'id': 17, 'order_sequence': 2, 'order_symbol': '1W8E5J7M2V', 'state': 'paid', 'data': <String, dynamic>{}},
      ],
    };
    final blueprint = BlueprintModel.fromJson(data);
    expect(blueprint.objects,isNull);
    expect(blueprint.groups,isNull);
    expect(blueprint.configuration,isNull);
    expect(blueprint.backgroundSvg,isNull);
    expect(()=>BlueprintModel.fromJson({'id':1,'objects':[]}),throwsStateError);
    expect(BlueprintModel.fromLegacyJson({'id':1,'objects':[]}).objects,isEmpty);
    expect(blueprint.orders!.single.id, 17);
    expect(blueprint.orders!.single.orderSequence, 2);
    expect(blueprint.orders!.single.orderSymbol, '1W8E5J7M2V');
    // The pre-fix projection returned neither field and failed this exact caller.
    final oldOrder = Map<String, dynamic>.from((data['orders'] as List).single)
      ..remove('order_sequence') ..remove('order_symbol');
    expect(() => BlueprintModel.fromJson({...data, 'orders': [oldOrder]}), throwsStateError);
  });
}
