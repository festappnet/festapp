import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/seat_adapter.dart';
import '../model/seat_slot.dart';
import '../model/venue_backdrop.dart';

/// Owns the indexed venue grid, viewport and transient presentation state.
class VenueSeatController<T, Id extends Object> extends ChangeNotifier {
  VenueSeatController({required this.adapter});

  final SeatAdapter<T, Id> adapter;
  final TransformationController transformationController =
      TransformationController();
  List<SeatSlot<T, Id>> slots = [];
  int rows = 1;
  int columns = 1;
  double seatSize = 40;
  VenueBackdrop? backdrop;
  double minScale = 1;
  bool isLayoutReady = false;
  GlobalKey? _layoutKey;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  List<T> get seats => slots.map((slot) => slot.seat).whereType<T>().toList();
  Set<Id> get selectedSeatIds => slots
      .where((slot) => slot.isSelected)
      .map((slot) => slot.seatId)
      .whereType<Id>()
      .toSet();

  void attachLayoutKey(GlobalKey key) {
    _layoutKey = key;
    _scheduleFit();
  }

  void loadPlan({
    required int rows,
    required int columns,
    required Iterable<T> seats,
    double seatSize = 40,
    VenueBackdrop? backdrop,
    Iterable<Id> initiallySelected = const [],
  }) {
    _validateDimensions(rows, columns, seatSize);
    final selected = initiallySelected.toSet();
    final byPosition = <SeatPosition, T>{};
    final ids = <Id>{};
    for (final seat in seats) {
      final position = adapter.positionOf(seat);
      if (position.row < 0 ||
          position.row >= rows ||
          position.column < 0 ||
          position.column >= columns) {
        throw ArgumentError.value(
          seat,
          'seats',
          'Seat coordinates must be inside the venue grid',
        );
      }
      if (byPosition.containsKey(position)) {
        throw ArgumentError('Duplicate seat position: $position');
      }
      final id = adapter.idOf(seat);
      if (!ids.add(id)) throw ArgumentError('Duplicate seat id: $id');
      byPosition[position] = seat;
    }

    this.rows = rows;
    this.columns = columns;
    this.seatSize = seatSize;
    this.backdrop = backdrop;
    slots = [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          _createSlot(
            SeatPosition(row, column),
            byPosition[SeatPosition(row, column)],
            selected,
          ),
    ];
    if (_layoutKey != null) _scheduleFit();
    notifyListeners();
  }

  SeatSlot<T, Id> _createSlot(
    SeatPosition position,
    T? seat,
    Set<Id> selected,
  ) {
    final id = seat == null ? null : adapter.idOf(seat);
    return SeatSlot<T, Id>(
      position: position,
      size: seatSize,
      seat: seat,
      seatId: id,
      status: seat == null ? null : adapter.statusOf(seat),
      label: seat == null ? null : adapter.labelOf?.call(seat),
      groupId: seat == null ? null : adapter.groupOf?.call(seat),
    )..isSelected = id != null && selected.contains(id);
  }

  bool canResize(int newRows, int newColumns) =>
      newRows > 0 &&
      newColumns > 0 &&
      slots
          .where((slot) => slot.seat != null)
          .every((slot) => slot.row < newRows && slot.column < newColumns);

  bool setDimensions(int newRows, int newColumns) {
    if (!canResize(newRows, newColumns)) return false;
    loadPlan(
      rows: newRows,
      columns: newColumns,
      seats: seats,
      seatSize: seatSize,
      backdrop: backdrop,
      initiallySelected: selectedSeatIds,
    );
    return true;
  }

  void setBackdrop(VenueBackdrop? value) {
    backdrop = value;
    notifyListeners();
  }

  SeatSlot<T, Id>? slotAt(int row, int column) {
    if (row < 0 || row >= rows || column < 0 || column >= columns) return null;
    return slots[row * columns + column];
  }

  SeatSlot<T, Id>? slotForId(Id id) {
    for (final slot in slots) {
      if (slot.seatId == id) return slot;
    }
    return null;
  }

  void replaceSeat(SeatSlot<T, Id> slot, T seat) {
    final target = slotAt(slot.row, slot.column);
    if (target == null) return;
    final position = adapter.positionOf(seat);
    if (position != target.position) {
      throw ArgumentError.value(seat, 'seat', 'Seat position cannot change');
    }
    final id = adapter.idOf(seat);
    if (slots.any((other) => other != target && other.seatId == id)) {
      throw ArgumentError('Duplicate seat id: $id');
    }
    target
      ..seat = seat
      ..seatId = id
      ..status = adapter.statusOf(seat)
      ..label = adapter.labelOf?.call(seat)
      ..groupId = adapter.groupOf?.call(seat);
    notifyListeners();
  }

  void refreshSeat(T seat) {
    final target = slotForId(adapter.idOf(seat));
    if (target != null) replaceSeat(target, seat);
  }

  void setSelection(SeatSlot<T, Id> slot, bool selected, {bool? pending}) {
    final target = slotAt(slot.row, slot.column);
    if (target == null || target.seat == null) return;
    target.isSelected = selected;
    if (pending != null) target.isPending = pending;
    notifyListeners();
  }

  void setPending(SeatSlot<T, Id> slot, bool pending) {
    final target = slotAt(slot.row, slot.column);
    if (target == null) return;
    target.isPending = pending;
    notifyListeners();
  }

  void addSeat(T seat, {bool highlightGroup = false}) {
    final position = adapter.positionOf(seat);
    final target = slotAt(position.row, position.column);
    if (target == null) {
      throw ArgumentError.value(seat, 'seat', 'Seat is outside the venue grid');
    }
    if (target.seat != null && !identical(target.seat, seat)) {
      throw StateError(
        'Position (${target.row}, ${target.column}) is occupied',
      );
    }
    replaceSeat(target, seat);
    target.isGroupHighlighted = highlightGroup;
  }

  T? removeSeat(SeatSlot<T, Id> slot) {
    final target = slotAt(slot.row, slot.column);
    final removed = target?.seat;
    if (target != null) {
      target
        ..seat = null
        ..seatId = null
        ..status = null
        ..label = null
        ..groupId = null
        ..isSelected = false
        ..isPending = false
        ..isGroupHighlighted = false
        ..isSwapHighlighted = false
        ..isTooltipHighlighted = false;
      notifyListeners();
    }
    return removed;
  }

  void setSwapHighlight(SeatSlot<T, Id> slot, bool highlighted) {
    final target = slotAt(slot.row, slot.column);
    if (target == null) return;
    target.isSwapHighlighted = highlighted;
    notifyListeners();
  }

  void highlightGroup(Object? groupId) {
    for (final slot in slots) {
      slot.isGroupHighlighted = groupId != null && slot.groupId == groupId;
    }
    notifyListeners();
  }

  void showTooltipFor(SeatSlot<T, Id>? slot) {
    for (final candidate in slots) {
      candidate.isTooltipHighlighted = candidate == slot;
    }
    notifyListeners();
  }

  void _scheduleFit() {
    if (_disposed) return;
    isLayoutReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) fitToViewport();
    });
  }

  void fitToViewport() {
    if (_disposed) return;
    final context = _layoutKey?.currentContext;
    final renderBox = context?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final layoutWidth = columns * seatSize;
    final layoutHeight = rows * seatSize;
    if (layoutWidth <= 0 || layoutHeight <= 0) return;
    minScale = math
        .min(
          renderBox.size.width / layoutWidth,
          renderBox.size.height / layoutHeight,
        )
        .clamp(0.01, 1.0)
        .toDouble();
    final x = (renderBox.size.width - layoutWidth * minScale) / 2;
    final y = (renderBox.size.height - layoutHeight * minScale) / 2;
    // InteractiveViewer and viewport bounds use the maximum scale across
    // all three axes. Keep Z consistent so zooming out reports the true scale.
    transformationController.value = Matrix4.diagonal3Values(
      minScale,
      minScale,
      minScale,
    )..setTranslationRaw(x, y, 0);
    isLayoutReady = true;
    notifyListeners();
  }

  static void _validateDimensions(int rows, int columns, double seatSize) {
    if (rows <= 0 || columns <= 0) {
      throw ArgumentError('Venue grid dimensions must be positive');
    }
    if (!seatSize.isFinite || seatSize <= 0) {
      throw ArgumentError.value(seatSize, 'seatSize', 'Must be positive');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    transformationController.dispose();
    super.dispose();
  }
}
