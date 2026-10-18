import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/eshop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/email_preview_context_loader.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';

ProductsEditBundle bundle(List<ProductModel> products) => ProductsEditBundle(
      products: products,
      productTypes: [ProductTypeModel(id: 1, title: 'Vstupné')],
      inventoryPools: [],
      inventoryContexts: [],
      forms: [],
    );
void main() {
  test(
      'occasion sampler uses scoped catalog with actual prices in one currency',
      () async {
    final occasion = OccasionModel(
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        id: 42,
        title: 'Podzimní koncert',
        link: 'concert');
    var requests = 0;
    final result =
        await loadEmailPreviewContext(occasion, loadProducts: (link) async {
      expect(link, 'concert');
      requests++;
      return bundle([
        ProductModel(
            id: 1,
            title: 'Skryté',
            price: 999,
            isHidden: true,
            currencyCode: 'CZK'),
        ProductModel(
            id: 2,
            title: 'Přízemí',
            price: 750,
            productTypeId: 1,
            currencyCode: 'CZK'),
        ProductModel(id: 3, title: 'Jiná měna', price: 30, currencyCode: 'EUR'),
        ProductModel(
            id: 4,
            title: 'Balkon',
            price: 450,
            productTypeId: 1,
            currencyCode: 'CZK'),
      ]);
    });
    expect(requests, 1);
    expect(result.unavailable, isFalse);
    expect(result.context.products.map((p) => p.title), ['Přízemí', 'Balkon']);
    final examples = EmailPreviewExamples.fromJson(
        jsonDecode(File('assets/email_templates/preview_examples.json')
            .readAsStringSync()) as Map<String, dynamic>,
        context: result.context);
    expect(examples.usesOccasionProducts, isTrue);
    final scenario = examples.scenariosFor('TICKET_ORDER_CONFIRMATION').first;
    expect(scenario.values['occasionTitle'], 'Podzimní koncert');
    expect(scenario.values['fullOrder'], contains('Vstupné: Přízemí'));
    expect(scenario.values['fullOrder'], contains('Balkon'));
    expect(scenario.values['amount'], contains('1\u00a0200'));
    expect(scenario.values['fullOrder'], isNot(contains('Jiná měna')));
  });
  test(
      'denied catalog yields a labelled model fallback retaining occasion title',
      () async {
    final result = await loadEmailPreviewContext(
        OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            id: 42,
            title: 'Ples',
            link: 'ball'),
        loadProducts: (_) async => throw StateError('not permitted'));
    expect(result.unavailable, isTrue);
    expect(result.context.products, isEmpty);
    expect(result.context.occasionTitle, 'Ples');
  });
  test('unit templates never query an unrelated occasion', () async {
    var called = false;
    final result = await loadEmailPreviewContext(null, loadProducts: (_) async {
      called = true;
      return bundle([]);
    });
    expect(called, isFalse);
    expect(result.unavailable, isFalse);
    expect(result.context.products, isEmpty);
  });
  test(
      'empty or exclusively free catalog uses coherent model financial examples',
      () async {
    final result = await loadEmailPreviewContext(
        OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            id: 42,
            title: 'Volný vstup',
            link: 'free'),
        loadProducts: (_) async =>
            bundle([ProductModel(id: 1, title: 'Zdarma', price: 0)]));
    expect(result.context.products, isEmpty);
    expect(result.unavailable, isFalse);
  });
}
