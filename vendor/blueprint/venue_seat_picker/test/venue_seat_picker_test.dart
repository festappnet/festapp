import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  VenueSeat seat(
    String id,
    int column, {
    SeatStatus status = SeatStatus.available,
  }) => VenueSeat(
    id: id,
    position: SeatPosition(0, column),
    status: status,
    label: id,
  );

  VenueSeatController<VenueSeat, Object> controller(
    List<VenueSeat> seats, {
    Iterable<Object> selected = const [],
  }) => VenueSeatController<VenueSeat, Object>(adapter: venueSeatAdapter)
    ..loadPlan(
      rows: 1,
      columns: seats.length,
      seats: seats,
      initiallySelected: selected,
    );

  testWidgets('rolls an optimistic selection back when rejected', (
    tester,
  ) async {
    final original = seat('A1', 0);
    final seats = controller([original]);
    final request = Completer<bool>();
    final selections = <Set<Object>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: VenueSeatPicker<VenueSeat, Object>(
            controller: seats,
            onSelectionRequested: (_) => request.future,
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(VenueSeatMarker));
    await tester.pump();
    expect(seats.slotAt(0, 0)?.isSelected, isTrue);
    expect(seats.slotAt(0, 0)?.isPending, isTrue);
    expect(original.status, SeatStatus.available);

    request.complete(false);
    await tester.pump();
    expect(seats.slotAt(0, 0)?.isSelected, isFalse);
    expect(selections.last, isEmpty);
    seats.dispose();
  });

  testWidgets('enforces the selection limit without calling the backend', (
    tester,
  ) async {
    final seats = controller([seat('A1', 0), seat('A2', 1)], selected: ['A1']);
    var requests = 0;
    var limits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: VenueSeatPicker<VenueSeat, Object>(
            controller: seats,
            maxSelectedSeats: 1,
            onSelectionRequested: (_) async {
              requests++;
              return true;
            },
            onSelectionLimitReached: () => limits++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(VenueSeatMarker).last);
    await tester.pump();
    expect(requests, 0);
    expect(limits, 1);
    seats.dispose();
  });

  testWidgets('rolls back and reports a thrown reservation error', (
    tester,
  ) async {
    final seats = controller([seat('A1', 0)]);
    Object? reported;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: VenueSeatPicker<VenueSeat, Object>(
            controller: seats,
            onSelectionRequested: (_) async =>
                throw StateError('reservation failed'),
            onSelectionError: (error, stackTrace) => reported = error,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(VenueSeatMarker));
    await tester.pump();

    expect(reported, isA<StateError>());
    expect(seats.slotAt(0, 0)?.isSelected, isFalse);
    seats.dispose();
  });

  testWidgets('long press opens the tooltip without selecting', (tester) async {
    final seats = controller([seat('A1', 0)]);
    var requests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: VenueSeatPicker<VenueSeat, Object>(
            controller: seats,
            onSelectionRequested: (_) async {
              requests++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.longPress(find.byType(VenueSeatMarker));
    await tester.pump();

    expect(find.text('A1'), findsOneWidget);
    expect(requests, 0);
    seats.dispose();
  });

  testWidgets('settles a pending request after the picker unmounts', (
    tester,
  ) async {
    final seats = controller([seat('A1', 0)]);
    final request = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: VenueSeatPicker<VenueSeat, Object>(
            controller: seats,
            onSelectionRequested: (_) => request.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(VenueSeatMarker));
    await tester.pump();
    expect(seats.slotAt(0, 0)?.isSelected, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    request.complete(false);
    await tester.pump();

    expect(seats.slotAt(0, 0)?.isSelected, isFalse);
    seats.dispose();
  });

  testWidgets('ignores duplicate taps while a request is pending', (
    tester,
  ) async {
    final seats = controller([seat('A1', 0)]);
    final request = Completer<bool>();
    var requests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: VenueSeatPicker<VenueSeat, Object>(
            controller: seats,
            onSelectionRequested: (_) {
              requests++;
              return request.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(VenueSeatMarker));
    await tester.tap(find.byType(VenueSeatMarker));
    await tester.pump();

    expect(requests, 1);
    request.complete(true);
    await tester.pump();
    seats.dispose();
  });
}
