import 'package:festapp_core/eshop.dart';

/// Persistence seam shared by the live queue editor and private setup drafts.
/// The editor owns interaction; each adapter owns its transaction boundary.
abstract interface class ProductPriceWaveActions {
  Future<ProductPriceWave> create(DateTime time);
  Future<void> move(ProductPriceWave wave, DateTime time);
  Future<void> saveTarget(
      ProductPriceWave wave, ProductModel product, double? price, bool? hidden);
  Future<void> cancel(ProductPriceWave wave);
}
