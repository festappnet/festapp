import 'package:flutter/material.dart';

import '../controller/venue_seat_controller.dart';
import '../model/seat_adapter.dart';
import '../model/seat_slot.dart';
import '../model/seat_status.dart';
import 'venue_seat_style.dart';
import 'venue_seat_viewer.dart';

/// Immutable editing operations for an application's seat model.
class SeatEditingDelegate<T> {
  const SeatEditingDelegate({required this.create, required this.withStatus});

  final T Function(SeatPosition position, SeatStatus status) create;
  final T Function(T seat, SeatStatus status) withStatus;
}

/// Grid editor for adding, removing and restyling venue seats.
class VenueSeatEditor<T, Id extends Object> extends StatefulWidget {
  const VenueSeatEditor({
    super.key,
    required this.controller,
    required this.editing,
    this.onChanged,
    this.statuses = const [SeatStatus.available, SeatStatus.blocked],
    this.allowErase = true,
    this.config = const VenueSeatViewConfig(),
  }) : assert(statuses.length > 0);

  final VenueSeatController<T, Id> controller;
  final SeatEditingDelegate<T> editing;
  final VoidCallback? onChanged;
  final List<SeatStatus> statuses;
  final bool allowErase;
  final VenueSeatViewConfig config;

  @override
  State<VenueSeatEditor<T, Id>> createState() => _VenueSeatEditorState<T, Id>();
}

class _VenueSeatEditorState<T, Id extends Object>
    extends State<VenueSeatEditor<T, Id>> {
  late SeatStatus _paintStatus = widget.statuses.first;
  bool _erase = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          IconButton(
            tooltip: 'Remove row',
            onPressed:
                widget.controller.canResize(
                  widget.controller.rows - 1,
                  widget.controller.columns,
                )
                ? () => _resize(
                    widget.controller.rows - 1,
                    widget.controller.columns,
                  )
                : null,
            icon: const Icon(Icons.remove),
          ),
          Text('${widget.controller.rows} rows'),
          IconButton(
            tooltip: 'Add row',
            onPressed: () =>
                _resize(widget.controller.rows + 1, widget.controller.columns),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Remove column',
            onPressed:
                widget.controller.canResize(
                  widget.controller.rows,
                  widget.controller.columns - 1,
                )
                ? () => _resize(
                    widget.controller.rows,
                    widget.controller.columns - 1,
                  )
                : null,
            icon: const Icon(Icons.remove),
          ),
          Text('${widget.controller.columns} columns'),
          IconButton(
            tooltip: 'Add column',
            onPressed: () =>
                _resize(widget.controller.rows, widget.controller.columns + 1),
            icon: const Icon(Icons.add),
          ),
          for (final status in widget.statuses)
            ChoiceChip(
              label: Text(status.name),
              selected: !_erase && _paintStatus == status,
              onSelected: (_) => setState(() {
                _paintStatus = status;
                _erase = false;
              }),
            ),
          if (widget.allowErase)
            ChoiceChip(
              label: const Text('erase'),
              selected: _erase,
              onSelected: (_) => setState(() => _erase = true),
            ),
        ],
      ),
      Expanded(
        child: VenueSeatViewer<T, Id>(
          controller: widget.controller,
          editorMode: true,
          config: widget.config,
          onSeatPressed: _paint,
        ),
      ),
    ],
  );

  void _resize(int rows, int columns) {
    if (widget.controller.setDimensions(rows, columns)) {
      widget.onChanged?.call();
      setState(() {});
    }
  }

  void _paint(SeatSlot<T, Id> slot) {
    if (_erase) {
      widget.controller.removeSeat(slot);
    } else if (slot.seat == null) {
      widget.controller.addSeat(
        widget.editing.create(slot.position, _paintStatus),
      );
    } else {
      widget.controller.replaceSeat(
        slot,
        widget.editing.withStatus(slot.seat as T, _paintStatus),
      );
    }
    widget.onChanged?.call();
    setState(() {});
  }
}
