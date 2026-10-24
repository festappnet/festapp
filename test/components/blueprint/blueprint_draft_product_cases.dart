import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_configuration.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_blueprint.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() {
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  test('draft blueprint adapts legacy seats without copying occupancy', () {
    final source = {
      'id': 3, 'configuration': {'dimensions': {'width': 4, 'height': 4}},
      'objects': [{'id': 9, 'type': 'spot', 'x': 1, 'y': 1},
        {'type': 'table', 'x': 0, 'y': 0, 'title': 'Stage'}],
      'spots': [{'id': 9, 'product': 7, 'title': 'A1', 'order_product_ticket': 6}],
      'groups': <dynamic>[],
    };
    final draft = <String,dynamic>{'blueprintMode': 'Bez plánku',
      'formDraft': {'fields': <dynamic>[]}};
    final owner = OccasionSetupBlueprint(draft);
    owner.importPlan(source);
    expect(owner.modeId, 'copy');
    expect(owner.seatCount, 1);
    expect((draft['blueprintObjects'] as List).first['product'], 7);
    expect((draft['blueprintObjects'] as List).first.containsKey('order_product_ticket'), false);
    expect((source['spots'] as List).first['order_product_ticket'], 6);
    expect((draft['formDraft']['fields'] as List).single['type'], 'spot');
    expect(() => owner.importPlan({'objects': [{'type':'unknown'}]}), throwsFormatException);
    expect(owner.seatCount, 1, reason: 'Failed adaptation preserves the previous plan');
    owner.clear();
    expect(owner.seatCount, 0);
    expect(draft['formDraft']['fields'], isEmpty);
    expect(owner.ready, true);
  });
  test('inline modern plan retains distinct products, names and numeric dimensions', () {
    final draft = <String,dynamic>{'formEnabled':true,
      'formDraft': {'fields': [
        {'type':'product_type','product_type_data':{'id':1,'type':'spot','products':[
          {'id':7,'title':'Standard','price':100,'currency_code':'CZK'},
          {'id':8,'title':'VIP','price':200,'currency_code':'CZK'}]}}
      ]}};
    final owner = OccasionSetupBlueprint(draft);
    owner.importPlan({
      'id':2, 'configuration': {'dimensions':{'width':4.0,'height':3.0}},
      'objects':[
        {'type':'spot','x':1.0,'y':1.0,'product':7,'title':'A1'},
        {'type':'spot','x':2,'y':1,'product':8,'title':'A2'},
        {'type':'table','x':0,'y':0,'title':'Stage'}], 'groups':<dynamic>[]});
    expect(owner.seatCount, 2);
    expect(owner.ready, true);
    final plan = owner.plan();
    expect(plan.configuration!.width, 4);
    expect(plan.objects!.take(2).map((o) => o.product!.id), [7,8]);
    expect(plan.objects!.take(2).map((o) => o.title), ['A1','A2']);
    owner.clear();
    expect(draft['formDraft']['fields'].length, 1,
        reason:'Disabling seats retains the product catalog for normal sales');
    expect((draft['formDraft']['fields'] as List).any((f) => f['type']=='spot'), false);
  });
  test('legacy mode IDs and absent modes have deterministic migration', () {
    expect(OccasionSetupBlueprint({'blueprintMode':'Nový'}).modeId, 'new');
    expect(OccasionSetupBlueprint({'blueprintMode':'Převzít'}).modeId, 'copy');
    expect(OccasionSetupBlueprint({'blueprintObjects':[{'type':'spot'}]}).modeId, 'copy');
  });
  test('decorations and empty new plans cannot finish setup', () {
    final draft = <String,dynamic>{'blueprintMode':'Nový', 'formEnabled':true,
      'blueprintObjects':[{'type':'table','x':0,'y':0}]};
    expect(OccasionSetupBlueprint(draft).ready, false);
  });
  testWidgetsWithEnvironment(() => _environment,
      'draft editor retains seat products and names after loading',
      (tester) async {
    final product = ProductModel(
        id: 7,
        title: 'VIP',
        price: 650,
        currencyCode: 'CZK',
        productTypeString: ProductModel.spotType);
    final group = BlueprintGroupModel(id: 1, title: 'A', product: product);
    final seat = BlueprintObjectModel(
        id: 11,
        x: 1,
        y: 1,
        title: 'A1',
        type: 'spot',
        state: 'available',
        product: product,
        groupId: 1)
      ..group = group;
    group.objects.add(seat);
    final plan = BlueprintModel(
        configuration: BlueprintConfiguration(width: 2, height: 2),
        groups: [group],
        objects: [seat],
        products: [product]);
    BlueprintModel? saved;
    await _environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintTab.prototype(
                prototypeBlueprint: plan,
                onPrototypeSave: (value) => saved = value)));
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(BlueprintTab));
    await editor.saveChanges();
    await tester.pumpAndSettle();
    expect(saved!.objects!.single.title, 'A1');
    expect(saved!.objects!.single.product!.id, 7);
    expect(saved!.objects!.single.product!.price, 650);
    expect(saved!.spotProducts.single.title, 'VIP');
    saved = null;
    await _environment.pumpWidget(tester, const SizedBox());
    expect(saved, isNull, reason: 'Disposing the editor must not save discarded changes');
    expect(plan.objects!.single.product, same(product),
        reason: 'source remains unchanged');
  });
}
