import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion_settings/occasion_save_state.dart';

void main() {
  test('failed occasion save always leaves the saving state', () async {
    final states = <bool>[];

    await expectLater(
      runOccasionSaveAction(
        setSaving: states.add,
        action: () async => throw StateError('save failed'),
      ),
      throwsStateError,
    );

    expect(states, [true, false]);
  });
}
