import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';

void main() {
  group('ProductModel.metaSurchargeAmount / metaSurchargeCurrency', () {
    test('setter writes into data.meta_surcharge', () {
      final product = ProductModel();
      product.metaSurchargeAmount = 200.0;
      product.metaSurchargeCurrency = 'EUR';

      final ms = product.data?[TbEshop.products.data_meta_surcharge] as Map?;
      expect(ms, isNotNull);
      expect(ms!['amount'], 200.0);
      expect(ms['currency'], 'EUR');
    });

    test('getters read from data.meta_surcharge', () {
      final product = ProductModel();
      product.data = {
        TbEshop.products.data_meta_surcharge: {
          'amount': 150.0,
          'currency': 'CZK'
        },
      };
      expect(product.metaSurchargeAmount, 150.0);
      expect(product.metaSurchargeCurrency, 'CZK');
    });

    test('amount setter to 0 removes the entry', () {
      final product = ProductModel();
      product.metaSurchargeAmount = 100.0;
      product.metaSurchargeAmount = 0;
      expect(product.data?[TbEshop.products.data_meta_surcharge], isNull);
    });

    test('amount setter to null removes the entry', () {
      final product = ProductModel();
      product.metaSurchargeAmount = 100.0;
      product.metaSurchargeAmount = null;
      expect(product.data?[TbEshop.products.data_meta_surcharge], isNull);
    });

    test('currency setter removes entry when amount missing', () {
      final product = ProductModel();
      product.metaSurchargeCurrency = 'EUR';
      // Without an amount, currency-only is dropped — symmetrical with deposit pattern.
      expect(product.data?[TbEshop.products.data_meta_surcharge], isNull);
    });

    test('getter returns null when amount is 0 in underlying data', () {
      final product = ProductModel();
      product.data = {
        TbEshop.products.data_meta_surcharge: {'amount': 0, 'currency': 'EUR'},
      };
      expect(product.metaSurchargeAmount, isNull);
    });

    test('amount accepts string from JSON and parses it', () {
      final product = ProductModel();
      product.data = {
        TbEshop.products.data_meta_surcharge: {
          'amount': '125.5',
          'currency': 'EUR'
        },
      };
      expect(product.metaSurchargeAmount, 125.5);
    });
  });
}
