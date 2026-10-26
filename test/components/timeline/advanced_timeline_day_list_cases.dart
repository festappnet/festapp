import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/timeline/advanced_timeline_day_list.dart';

void main() {
  test('day list keeps a gutter without double-counting shell navigation', () {
    expect(
      dayListContentPadding.bottom,
      16,
    );
  });
}
