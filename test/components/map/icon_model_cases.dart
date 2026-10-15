import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/icon_model.dart';

void main() {
  test('normalizes legacy icon presentation data at the model boundary', () {
    expect(IconModel(data: null).renderableSvgData, isNull);
    expect(IconModel(data: '  ').renderableSvgData, isNull);
    expect(IconModel(data: 'not svg').renderableSvgData, isNull);
    expect(
      IconModel(data: '  <svg viewBox="0 0 1 1"></svg>  ').renderableSvgData,
      '<svg viewBox="0 0 1 1"></svg>',
    );

    expect(IconModel(link: null).displayLabel, IconModel.missingLabel);
    expect(IconModel(link: '  ').displayLabel, IconModel.missingLabel);
    expect(IconModel(link: '  church  ').displayLabel, 'church');
    expect(IconModel(link: '  church  ').normalizedLink, 'church');
  });
}
