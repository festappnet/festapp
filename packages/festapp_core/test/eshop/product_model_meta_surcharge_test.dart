import 'package:test/test.dart';
import 'package:festapp_core/eshop.dart';

void main() {
  group('product_model_meta_surcharge', registerCases);
}

void registerCases() {
  group('ProductModel.metaSurchargeAmount / metaSurchargeCurrency', () {
    test('setter writes into data.meta_surcharge', () {
      var product = ProductModel();
      product = product.withMetaSurchargeAmount(200.0);
      product = product.withMetaSurchargeCurrency('EUR');

      final ms = product.data?['meta_surcharge'] as Map?;
      expect(ms, isNotNull);
      expect(ms!['amount'], 200.0);
      expect(ms['currency'], 'EUR');
    });

    test('getters read from data.meta_surcharge', () {
      var product = ProductModel();
      product = product.copyWith(
        data: {
          'meta_surcharge': {'amount': 150.0, 'currency': 'CZK'},
        },
      );
      expect(product.metaSurchargeAmount, 150.0);
      expect(product.metaSurchargeCurrency, 'CZK');
    });

    test('amount setter to 0 removes the entry', () {
      var product = ProductModel();
      product = product.withMetaSurchargeAmount(100.0);
      product = product.withMetaSurchargeAmount(0);
      expect(product.data?['meta_surcharge'], isNull);
    });

    test('amount setter to null removes the entry', () {
      var product = ProductModel();
      product = product.withMetaSurchargeAmount(100.0);
      product = product.withMetaSurchargeAmount(null);
      expect(product.data?['meta_surcharge'], isNull);
    });

    test('currency setter removes entry when amount missing', () {
      var product = ProductModel();
      product = product.withMetaSurchargeCurrency('EUR');
      // Without an amount, currency-only is dropped — symmetrical with deposit pattern.
      expect(product.data?['meta_surcharge'], isNull);
    });

    test('getter returns null when amount is 0 in underlying data', () {
      var product = ProductModel();
      product = product.copyWith(
        data: {
          'meta_surcharge': {'amount': 0, 'currency': 'EUR'},
        },
      );
      expect(product.metaSurchargeAmount, isNull);
    });

    test('amount accepts string from JSON and parses it', () {
      var product = ProductModel();
      product = product.copyWith(
        data: {
          'meta_surcharge': {'amount': '125.5', 'currency': 'EUR'},
        },
      );
      expect(product.metaSurchargeAmount, 125.5);
    });
  });
}
