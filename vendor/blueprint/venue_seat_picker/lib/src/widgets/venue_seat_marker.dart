import 'package:flutter/material.dart';

import '../model/seat_status.dart';
import 'venue_seat_style.dart';

/// Default marker used for one seat or an empty editor slot.
class VenueSeatMarker extends StatelessWidget {
  const VenueSeatMarker({
    super.key,
    required this.status,
    this.selected = false,
    this.pending = false,
    this.size = 40,
    this.isSwapHighlighted = false,
    this.isGroupHighlighted = false,
    this.isTooltipHighlighted = false,
    this.theme = const VenueSeatThemeData(),
  });

  final SeatStatus? status;
  final bool selected;
  final bool pending;
  final double size;
  final bool isSwapHighlighted;
  final bool isGroupHighlighted;
  final bool isTooltipHighlighted;
  final VenueSeatThemeData theme;

  @override
  Widget build(BuildContext context) {
    final visible =
        status != null ||
        isSwapHighlighted ||
        isGroupHighlighted ||
        isTooltipHighlighted;
    final border = isSwapHighlighted
        ? Border.all(color: theme.selectionBorder, width: 2)
        : isGroupHighlighted || isTooltipHighlighted
        ? Border.all(
            color:
                theme.highlightBorder ?? Theme.of(context).colorScheme.primary,
            width: 2,
          )
        : null;
    return Opacity(
      opacity: pending ? .58 : 1,
      child: SizedBox.square(
        dimension: size,
        child: Container(
          margin: visible ? EdgeInsets.all(selected ? .8 : 2.5) : null,
          decoration: BoxDecoration(
            color: selected
                ? theme.selected
                : status == null
                ? Colors.transparent
                : theme.colorFor(status!),
            borderRadius: BorderRadius.circular(2.5),
            border: border,
          ),
          child: pending
              ? Padding(
                  padding: EdgeInsets.all(size * .28),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : selected
              ? Icon(Icons.check, size: size * .7, color: theme.checkColor)
              : status == SeatStatus.booked
              ? CustomPaint(painter: _CrossPainter(theme.bookedMarkColor))
              : null,
        ),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.shortestSide * .28;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .8;
    canvas
      ..drawLine(
        Offset(inset, inset),
        Offset(size.width - inset, size.height - inset),
        paint,
      )
      ..drawLine(
        Offset(size.width - inset, inset),
        Offset(inset, size.height - inset),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) =>
      oldDelegate.color != color;
}
