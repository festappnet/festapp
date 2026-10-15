import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/information/information_expansion_state.dart';
import 'package:fstapp/components/information/information_model.dart';

void main() {
  test('keeps all user-opened items expanded when information is refreshed',
      () {
    final expandedIds = {1};
    updateExpandedInformationIds(expandedIds, 2, true);

    final refreshed = [
      InformationModel(id: 1, title: 'Program'),
      InformationModel(id: 2, title: 'Ubytování'),
    ];

    applyInformationExpansionState(refreshed, expandedIds);

    expect(expandedIds, {1, 2});
    expect(refreshed[0].isExpanded, isTrue);
    expect(refreshed[1].isExpanded, isTrue);
  });

  test('closing an item only closes that item', () {
    final expandedIds = {1, 2};

    updateExpandedInformationIds(expandedIds, 2, false);

    expect(expandedIds, {1});
  });
}
