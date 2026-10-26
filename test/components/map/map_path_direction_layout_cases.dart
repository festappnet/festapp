import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_direction_marker.dart';

void main() {
  test('direction glyph has a readable slender silhouette', () {
    final size = MapDirectionMarker.sizeFor(16);

    expect(size.width, lessThan(size.height));
    expect(size.height, 16);
  });
}
