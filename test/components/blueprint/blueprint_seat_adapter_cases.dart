import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('BlueprintObjectModel satisfies the package seat contract', () {
    final object = BlueprintObjectModel(
      id: 42,
      x: 3,
      y: 2,
      title: 'A1',
      state: BlueprintObjectModel.blackType,
    );

    expect(blueprintSeatAdapter.idOf(object), 42);
    expect(blueprintSeatAdapter.positionOf(object), const SeatPosition(2, 3));
    expect(blueprintSeatAdapter.statusOf(object), SeatStatus.blocked);
    expect(object.seatState, BlueprintSeatState.blocked);

    object.seatState = BlueprintSeatState.selectedByMe;
    expect(object.stateEnum, BlueprintSeatState.selectedByMe);
    expect(object.state, BlueprintObjectModel.selectedByMeType);
    expect(blueprintSeatAdapter.statusOf(object), SeatStatus.available);
  });

  test('missing coordinates are rejected instead of becoming zero', () {
    final object = BlueprintObjectModel(id: 42);

    expect(() => blueprintSeatAdapter.positionOf(object), throwsStateError);
  });
}
