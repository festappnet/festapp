import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  VenueSeat seat(String id, int row, int column) =>
      VenueSeat(id: id, position: SeatPosition(row, column));

  test('builds a complete grid without mutating the host model', () {
    final original = seat('A1', 0, 0);
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 2, columns: 3, seats: [original]);

    expect(controller.slots, hasLength(6));
    expect(controller.slotAt(0, 0)?.seat, same(original));
    expect(controller.slotAt(1, 2)?.status, isNull);
    controller.setSelection(controller.slotAt(0, 0)!, true);
    expect(controller.selectedSeatIds, {'A1'});
    expect(original.status, SeatStatus.available);
    controller.dispose();
  });

  test('refreshes authoritative data by replacing the seat value', () {
    final original = seat('A1', 0, 0);
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 1, columns: 1, seats: [original]);

    final updated = original.copyWith(status: SeatStatus.booked);
    controller.refreshSeat(updated);
    expect(controller.slotAt(0, 0)?.seat, same(updated));
    expect(controller.slotAt(0, 0)?.status, SeatStatus.booked);
    expect(original.status, SeatStatus.available);
    controller.dispose();
  });

  test('rejects duplicate ids, positions and out-of-range seats', () {
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    );

    expect(
      () => controller.loadPlan(
        rows: 2,
        columns: 2,
        seats: [seat('A', 0, 0), seat('B', 0, 0)],
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.loadPlan(
        rows: 2,
        columns: 2,
        seats: [seat('A', 0, 0), seat('A', 0, 1)],
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.loadPlan(rows: 2, columns: 2, seats: [seat('A', 3, 0)]),
      throwsArgumentError,
    );
    controller.dispose();
  });

  test('refuses to resize across an occupied slot', () {
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 3, columns: 3, seats: [seat('C3', 2, 2)]);

    expect(controller.setDimensions(2, 3), isFalse);
    expect(controller.rows, 3);
    expect(controller.setDimensions(4, 3), isTrue);
    controller.dispose();
  });
}
