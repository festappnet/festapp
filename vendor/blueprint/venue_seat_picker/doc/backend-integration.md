# Backend integration

The package owns interaction state, not reservation authority. Your backend
must atomically reject a seat already held by another visitor.

## Optimistic reservation

```dart
Future<bool> reserveSeat(
  SeatSelectionRequest<MySeat, int> request,
) async {
  try {
    if (request.selected) {
      await reservations.hold(request.seatId);
    } else {
      await reservations.release(request.seatId);
    }
    return true;
  } on SeatAlreadyHeldException {
    return false;
  }
}
```

The visual selection changes immediately. A `false` result or exception rolls
it back. Use `onSelectionError` to report unexpected failures. Duplicate taps
are ignored while that seat has a pending request.

## Real-time updates

Map backend state to `SeatStatus` in your adapter and replace the authoritative
seat value:

```dart
void applyRemoteSeat(MySeat updated) {
  controller.refreshSeat(updated);
}
```

`SeatStatus` represents server-visible availability: `available`, `held`,
`booked`, `checkedIn` or `blocked`. The current visitor's selected IDs remain a
separate overlay in `controller.selectedSeatIds`.

## Recommended server contract

Send a stable seat ID, hold/release action, event or performance ID, and a
reservation revision or token. Treat success as authoritative, make release
idempotent, and broadcast committed status changes to connected clients.
Pricing, authentication, authorization and expiry remain application concerns.
