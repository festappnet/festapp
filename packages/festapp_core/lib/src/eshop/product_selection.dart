import 'product_model.dart';

/// The editor's saved selection includes row order, product identity and price.
/// Other product metadata does not turn a selection into an unsaved edit.
bool sameProductSelection(List<ProductModel> first, List<ProductModel> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if ((first[index].id, first[index].price) !=
        (second[index].id, second[index].price))
      return false;
  }
  return true;
}
