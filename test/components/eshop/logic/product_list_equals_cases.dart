import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';

// Re-create the extension for testing since it's private in products_dialog.dart
extension ProductListEquals on List<ProductModel> {
  bool equals(List<ProductModel> other) {
    if (length != other.length) return false;

    final thisMap = {for (var p in this) p.id: p.price};
    final otherMap = {for (var p in other) p.id: p.price};

    if (thisMap.keys.length != otherMap.keys.length) return false;
    if (!thisMap.keys.every((key) => otherMap.containsKey(key))) return false;

    for (final id in thisMap.keys) {
      if (thisMap[id] != otherMap[id]) {
        return false;
      }
    }
    return true;
  }
}

void main() {
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
      expect(list1.equals(list2), isTrue);
    });

    test('returns true for empty lists', () {
      final list1 = <ProductModel>[];
      final list2 = <ProductModel>[];
      expect(list1.equals(list2), isTrue);
    });

    test('returns false for different lengths', () {
      final list1 = [
        ProductModel(id: 1, price: 100.0),
      ];
      final list2 = [
        ProductModel(id: 1, price: 100.0),
        ProductModel(id: 2, price: 200.0),
      ];
      expect(list1.equals(list2), isFalse);
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
      expect(list1.equals(list2), isFalse);
    });

    test('returns false for different IDs', () {
      final list1 = [
        ProductModel(id: 1, price: 100.0),
      ];
      final list2 = [
        ProductModel(id: 2, price: 100.0),
      ];
      expect(list1.equals(list2), isFalse);
    });

    test('returns true regardless of order', () {
      final list1 = [
        ProductModel(id: 2, price: 200.0),
        ProductModel(id: 1, price: 100.0),
      ];
      final list2 = [
        ProductModel(id: 1, price: 100.0),
        ProductModel(id: 2, price: 200.0),
      ];
      expect(list1.equals(list2), isTrue);
    });

    test('handles null prices', () {
      final list1 = [
        ProductModel(id: 1, price: null),
      ];
      final list2 = [
        ProductModel(id: 1, price: null),
      ];
      expect(list1.equals(list2), isTrue);
    });

    test('returns false when one has null price and other does not', () {
      final list1 = [
        ProductModel(id: 1, price: null),
      ];
      final list2 = [
        ProductModel(id: 1, price: 100.0),
      ];
      expect(list1.equals(list2), isFalse);
    });

    test('handles duplicate IDs by last-wins in map', () {
      // When duplicates exist, the map will keep the last entry
      final list1 = [
        ProductModel(id: 1, price: 100.0),
        ProductModel(id: 1, price: 200.0),
      ];
      final list2 = [
        ProductModel(id: 1, price: 200.0),
      ];
      // list1 has length 2, list2 has length 1 → false
      expect(list1.equals(list2), isFalse);
    });
  });
}
