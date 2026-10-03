import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/eshop/report_strings.dart';

class ReportTimelineSeries {
  final String label;
  final Color color;
  final Map<DateTime, BigInt> amounts;
  final String? currency;
  const ReportTimelineSeries(this.label, this.color, this.amounts,
      {this.currency});
}

// Plot coordinates may be approximate; all displayed values use integer cents.
BigInt reportMinorUnits(String amount) {
  final parts = amount.split('.');
  if (parts.length > 2 || (parts.length == 2 && parts[1].length > 2)) {
    throw const FormatException('Expected a two-decimal payment');
  }
  return BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
}

String reportChartAmount(BigInt amount, String? currency) => currency == null
    ? amount.toString()
    : '${amount ~/ BigInt.from(100)},${(amount % BigInt.from(100)).toString().padLeft(2, '0')} $currency';

List<DateTime> reportChartDays(DateTime start, DateTime end) => [
      for (var day = start;
          !day.isAfter(end);
          day = day.add(const Duration(days: 1)))
        day,
    ];

class ReportTimelineChart extends StatefulWidget {
  final List<ReportTimelineSeries> series;
  final DateTime start, end;
  final String? currency;
  final bool cumulative;
  const ReportTimelineChart({
    super.key,
    required this.series,
    required this.start,
    required this.end,
    this.currency,
    required this.cumulative,
  });
  @override
  State<ReportTimelineChart> createState() => _ReportTimelineChartState();
}

class _ReportTimelineChartState extends State<ReportTimelineChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant ReportTimelineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.end != widget.end ||
        oldWidget.cumulative != widget.cumulative) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = reportChartDays(widget.start, widget.end);
    final amounts = [
      for (final series in widget.series) _amounts(series, days),
    ];
    final maximum =
        amounts.expand((x) => x).fold(BigInt.one, (a, b) => a > b ? a : b);
    final lastActivity = days.lastIndexWhere((day) => widget.series
        .any((s) => (s.amounts[day] ?? BigInt.zero) > BigInt.zero));
    final selected = math.min(
        _selected ?? (lastActivity < 0 ? days.length - 1 : lastActivity),
        days.length - 1);
    final axis =
        widget.currency == null && !widget.series.any((s) => s.currency != null)
            ? maximum.toDouble()
            : maximum.toDouble() / 100;
    final colors = Theme.of(context).colorScheme;
    void select(double x, double width) {
      final index = (x / width * math.max(1, days.length - 1)).round().clamp(
            0,
            days.length - 1,
          );
      if (index != _selected) setState(() => _selected = index);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              DateFormat('d. M. yyyy').format(days[selected]),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (var i = 0; i < widget.series.length; i++)
              Text(
                '${widget.series[i].label}: ${reportChartAmount(amounts[i][selected], widget.series[i].currency ?? widget.currency)}',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: widget.series[i].color),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 54,
              height: 200,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    NumberFormat.compact().format(axis),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    NumberFormat.compact().format(axis / 2),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text('0', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => MouseRegion(
                  onHover: (event) =>
                      select(event.localPosition.dx, constraints.maxWidth),
                  child: GestureDetector(
                    onTapDown: (event) =>
                        select(event.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragUpdate: (event) =>
                        select(event.localPosition.dx, constraints.maxWidth),
                    child: Semantics(
                      label: widget.series.map((s) => s.label).join(', '),
                      child: SizedBox(
                        height: 200,
                        child: CustomPaint(
                          painter: _TimelinePainter(
                            amounts: amounts,
                            maximum: maximum,
                            colors: widget.series.map((s) => s.color).toList(),
                            grid: colors.outlineVariant,
                            selected: selected,
                            bars:
                                !widget.cumulative && widget.series.length == 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(DateFormat('d. M.').format(widget.start))),
          Expanded(
              child: Text(DateFormat('d. M.').format(widget.end),
                  textAlign: TextAlign.end)),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final series in widget.series)
              Text(
                '${series.label} - ${ReportStrings.timelineTotal}: ${reportChartAmount(series.amounts.entries.where((e) => !e.key.isBefore(widget.start) && !e.key.isAfter(widget.end)).fold(BigInt.zero, (sum, e) => sum + e.value), series.currency ?? widget.currency)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }

  List<BigInt> _amounts(ReportTimelineSeries series, List<DateTime> days) {
    var sum = widget.cumulative
        ? series.amounts.entries
            .where((e) => e.key.isBefore(widget.start))
            .fold(BigInt.zero, (sum, e) => sum + e.value)
        : BigInt.zero;
    return [
      for (final day in days)
        (() {
          final value = series.amounts[day] ?? BigInt.zero;
          if (!widget.cumulative) return value;
          sum += value;
          return sum;
        })(),
    ];
  }
}

class _TimelinePainter extends CustomPainter {
  final List<List<BigInt>> amounts;
  final BigInt maximum;
  final List<Color> colors;
  final Color grid;
  final int? selected;
  final bool bars;
  _TimelinePainter({
    required this.amounts,
    required this.maximum,
    required this.colors,
    required this.grid,
    required this.selected,
    required this.bars,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        gridPaint,
      );
    }
    for (var s = 0; s < amounts.length; s++) {
      final values = amounts[s];
      final path = Path();
      final paint = Paint()
        ..color = colors[s]
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? size.width / 2
            : i * size.width / (values.length - 1);
        final y = size.height * (1 - values[i].toDouble() / maximum.toDouble());
        if (bars) {
          final width = math.min(22.0, size.width / values.length * 0.7);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(
                math.max(0, x - width / 2),
                y,
                math.min(size.width, x + width / 2),
                size.height,
              ),
              const Radius.circular(3),
            ),
            Paint()..color = colors[s],
          );
        } else {
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
          if (values.length == 1) {
            canvas.drawCircle(Offset(x, y), 4, Paint()..color = colors[s]);
          }
        }
      }
      if (!bars) canvas.drawPath(path, paint);
    }
    if (selected != null) {
      final count = amounts.first.length;
      final x =
          count == 1 ? size.width / 2 : selected! * size.width / (count - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      for (var s = 0; s < amounts.length; s++) {
        final y = size.height *
            (1 - amounts[s][selected!].toDouble() / maximum.toDouble());
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = colors[s]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) => true;
}
