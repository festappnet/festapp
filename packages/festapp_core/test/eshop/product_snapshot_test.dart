import 'dart:convert';
import 'package:festapp_core/eshop.dart';
import 'package:test/test.dart';

void main() {
  test(
    'editor blueprint usage survives product joins and remains read-only',
    () {
      final product = ProductModel.fromJson({
        'id': 7,
        'is_used_in_blueprint': true,
      });
      expect(product.isUsedInBlueprint, isTrue);
      expect(
        product.copyWith(formTitles: 'Form', price: 450).isUsedInBlueprint,
        isTrue,
      );
      expect(
        ProductModel.fromJson({
          'is_used_in_blueprint': false,
        }).isUsedInBlueprint,
        isFalse,
      );
      expect(ProductModel.fromJson({}).isUsedInBlueprint, isNull);
      expect(product.toJson().containsKey('is_used_in_blueprint'), isFalse);
    },
  );
  test(
    'product codec preserves the existing nullable wire contract and unknown metadata',
    () {
      final wire = <String, dynamic>{
        'id': 7,
        'title': null,
        'description': '',
        'is_hidden': false,
        'price': '0',
        'currency_code': 'CZK',
        'product_type': 3,
        'occasion': 9,
        'order': 0,
        'maximum': 0,
        'data': {
          'unknown': {
            'values': [null, false, 0],
          },
          'meta_surcharge': {'amount': '-12.5', 'currency': 'EUR'},
        },
        'created_at': '2026-10-15T07:00:00Z',
        'ordered_count': 0,
      };
      final product = ProductModel.fromJson(wire);
      expect(product.toJson(), {
        'id': 7,
        'title': null,
        'description': '',
        'is_hidden': false,
        'price': 0.0,
        'currency_code': 'CZK',
        'product_type': 3,
        'occasion': 9,
        'order': 0,
        'maximum': 0,
        'data': wire['data'],
      });
      expect(product.price, isA<double>());
      expect(product.metaSurchargeAmount, -12.5);
      expect(ProductModel.fromJson({}).toJson()['data'], isNull);
      expect(ProductModel.fromJson({'data': {}}).toJson()['data'], isEmpty);
      expect(ProductModel.fromJson({'data': null}).toJson()['data'], isNull);
    },
  );

  test(
    'snapshots own nested data and explicit edits do not change the original',
    () {
      final values = [1, 2];
      final source = <String, dynamic>{
        'nested': {'values': values},
      };
      final original = ProductModel(id: 7, data: source, formIds: [9]);
      values.add(3);
      expect(original.data!['nested']['values'], [1, 2]);
      expect(
        () => (original.data!['nested']['values'] as List).add(3),
        throwsUnsupportedError,
      );
      expect(() => original.formIds.add(10), throwsUnsupportedError);
      final updated = original
          .withMetaSurchargeAmount(12)
          .withMetaSurchargeCurrency('EUR');
      expect(original.metaSurchargeAmount, isNull);
      expect(updated.metaSurchargeCurrency, 'EUR');
      expect(updated.data!['nested']['values'], [1, 2]);
      expect(updated.copyWith(title: null).title, isNull);
    },
  );

  test(
    'catalog joins flat products once without a product to type object cycle',
    () {
      final products = [ProductModel(id: 7, productTypeId: 3, title: 'Lunch')];
      final catalog = ProductCatalog(
        products: products,
        types: [ProductTypeModel(id: 3, title: 'Food')],
      );
      expect(
        identical(
          catalog.products.single,
          catalog.types.single.products!.single,
        ),
        isTrue,
      );
      expect(
        () => catalog.types.single.products!.clear(),
        throwsUnsupportedError,
      );
      final encoded =
          jsonDecode(jsonEncode(catalog.types.single.toJson())) as Map;
      expect(encoded['products'].single['id'], 7);
      expect(ProductTypeModel.fromJson({'id': 3}).toJson()['products'], isNull);
      expect(
        ProductTypeModel.fromJson({
          'id': 3,
          'products': [],
        }).toJson()['products'],
        isEmpty,
      );
    },
  );

  test(
    'price projection uses the supplied clock and server offset at wave boundaries',
    () {
      final product = ProductModel(
        priceClockOffset: const Duration(minutes: 2),
      );
      final wave = DateTime.utc(2026, 10, 15, 10);
      final local = wave.subtract(const Duration(minutes: 2));
      expect(product.priceTime(local), wave);
      expect(
        product
            .priceTime(local.subtract(const Duration(microseconds: 1)))
            .isBefore(wave),
        isTrue,
      );
      expect(
        product
            .priceTime(local.add(const Duration(microseconds: 1)))
            .isAfter(wave),
        isTrue,
      );
    },
  );
}
