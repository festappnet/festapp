# Getting started

`venue_seat_picker` separates authoritative seat data from interaction state.
Your widget owns a `VenueSeatController`, loads a venue plan, and renders a
viewer, picker or editor.

## Add the package

```yaml
dependencies:
  venue_seat_picker: ^0.1.0
```

## Own the controller

```dart
late final VenueSeatController<VenueSeat, Object> controller;

@override
void initState() {
  super.initState();
  controller = VenueSeatController(adapter: venueSeatAdapter)
    ..loadPlan(
      rows: 20,
      columns: 30,
      seats: seats,
      seatSize: 44,
    );
}

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

Coordinates are zero-based. Every seat ID and position must be unique and
inside the declared dimensions. A coordinate without a seat is an empty slot.

## Render a picker

```dart
VenueSeatPicker<VenueSeat, Object>(
  controller: controller,
  maxSelectedSeats: 6,
  onSelectionRequested: reserveSeat,
  onSelectionChanged: (selectedIds) {
    setState(() => checkoutSeatIds = selectedIds);
  },
  onSelectionLimitReached: showSelectionLimit,
  onSelectionError: reportSelectionError,
)
```

The picker immediately updates its selection overlay while
`onSelectionRequested` runs. Returning `false` or throwing restores the prior
selection. Repeated taps on the same seat are ignored while the request is
pending.

## Choosing a model

Use immutable `VenueSeat` when its JSON shape fits. For an existing domain
model, provide `SeatAdapter<T, Id>`. The adapter reads stable identity,
position, authoritative status, label and optional group without granting the
package write access to your model.

Call `controller.refreshSeat(updatedSeat)` when a server or state-management
update produces a new authoritative value.
