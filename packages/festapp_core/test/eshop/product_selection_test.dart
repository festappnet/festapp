import 'package:test/test.dart';
import 'package:festapp_core/eshop.dart';

void main() {
  group('product_list_equals', () {
    group('List<ProductModel>.equals', () {
      test('returns true for identical lists', () {
        final list1 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 2, price: 200.0),
        ];
        final list2 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 2, price: 200.0),
        ];
        expect(sameProductSelection(list1, list2), isTrue);
      });

      test('returns true for empty lists', () {
        final list1 = <ProductModel>[];
        final list2 = <ProductModel>[];
        expect(sameProductSelection(list1, list2), isTrue);
      });

      test('returns false for different lengths', () {
        final list1 = [ProductModel(id: 1, price: 100.0)];
        final list2 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 2, price: 200.0),
        ];
        expect(sameProductSelection(list1, list2), isFalse);
      });

      test('returns false for same IDs but different prices', () {
        final list1 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 2, price: 200.0),
        ];
        final list2 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 2, price: 300.0),
        ];
        expect(sameProductSelection(list1, list2), isFalse);
      });

      test('returns false for different IDs', () {
        final list1 = [ProductModel(id: 1, price: 100.0)];
        final list2 = [ProductModel(id: 2, price: 100.0)];
        expect(sameProductSelection(list1, list2), isFalse);
      });

      test('returns false when row order changes', () {
        final list1 = [
          ProductModel(id: 2, price: 200.0),
          ProductModel(id: 1, price: 100.0),
        ];
        final list2 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 2, price: 200.0),
        ];
        expect(sameProductSelection(list1, list2), isFalse);
      });

      test('handles null prices', () {
        final list1 = [ProductModel(id: 1, price: null)];
        final list2 = [ProductModel(id: 1, price: null)];
        expect(sameProductSelection(list1, list2), isTrue);
      });

      test('returns false when one has null price and other does not', () {
        final list1 = [ProductModel(id: 1, price: null)];
        final list2 = [ProductModel(id: 1, price: 100.0)];
        expect(sameProductSelection(list1, list2), isFalse);
      });

      test('handles duplicate IDs by last-wins in map', () {
        // When duplicates exist, the map will keep the last entry
        final list1 = [
          ProductModel(id: 1, price: 100.0),
          ProductModel(id: 1, price: 200.0),
        ];
        final list2 = [ProductModel(id: 1, price: 200.0)];
        // list1 has length 2, list2 has length 1 → false
        expect(sameProductSelection(list1, list2), isFalse);
      });
    });
  });
}
