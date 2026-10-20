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
    await _environment.pumpWidget(tester, const SizedBox());
    expect(saved!.objects!.single.title, 'A1');
    expect(saved!.objects!.single.product!.id, 7);
    expect(saved!.objects!.single.product!.price, 650);
    expect(saved!.spotProducts.single.title, 'VIP');
    expect(plan.objects!.single.product, same(product),
        reason: 'source remains unchanged');
  });
}
