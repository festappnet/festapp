import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/eshop/report_strings.dart';

class ReportTimelineSeries {
  final String label;
  final Color color;
  final Map<DateTime, BigInt> amounts;
  final String? currency;
  const ReportTimelineSeries(
    this.label,
    this.color,
    this.amounts, {
    this.currency,
  });
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

// Calendar anchors, rather than equally spaced labels with misleading dates.
List<DateTime> reportChartTicks(DateTime start, DateTime end) {
  final span = end.difference(start).inDays;
  return [
    start,
    for (var day = start.add(const Duration(days: 1));
        day.isBefore(end);
        day = day.add(const Duration(days: 1)))
      if (span >= 45
          ? day.day == 1
          : span >= 10
              ? day.weekday == DateTime.monday
              : true)
        day,
    if (end != start) end,
  ];
}

class _DateTick {
  final String label;
  final double fraction, left, width, height;
  const _DateTick(
      this.label, this.fraction, this.left, this.width, this.height);
}

List<_DateTick> _dateTicks(
    BuildContext context, DateTime start, DateTime end, double width) {
  final span = end.difference(start).inDays;
  final candidates = reportChartTicks(start, end).map((day) {
    final label = DateFormat('d. M.').format(day);
    final painter = TextPainter(
      text: TextSpan(text: label, style: Theme.of(context).textTheme.bodySmall),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final fraction = span == 0 ? 0.5 : day.difference(start).inDays / span;
    return _DateTick(
        label,
        fraction,
        (fraction * width - painter.width / 2).clamp(0, width - painter.width),
        painter.width,
        painter.height);
  }).toList();
  final ticks = <_DateTick>[candidates.first];
  for (final tick in candidates.skip(1)) {
    final isEnd = identical(tick, candidates.last);
    if (tick.left >= ticks.last.left + ticks.last.width + 12 &&
        (isEnd || tick.left + tick.width + 12 <= candidates.last.left)) {
      ticks.add(tick);
    }
  }
  return ticks;
}

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

Size _measureLegend(BuildContext context, Set<String> values, double maxWidth,
    TextStyle? style) {
  final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context));
  var width = 0.0, height = 0.0;
  for (final value in values) {
    painter.text = TextSpan(text: value, style: style);
    painter.layout(maxWidth: maxWidth);
    width = math.max(width, painter.width);
    height = math.max(height, painter.height);
  }
  painter.dispose();
  return Size(width, height);
}

class _ReportTimelineChartState extends State<ReportTimelineChart> {
  int? _selected;
  Object? _legendLayoutKey;
  List<Size>? _legendSizes;
  @override
  void didUpdateWidget(covariant ReportTimelineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _legendLayoutKey = null;
    _legendSizes = null;
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
    final peak =
        amounts.expand((x) => x).fold(BigInt.zero, (a, b) => a > b ? a : b);
    final money =
        widget.currency != null || widget.series.any((s) => s.currency != null);
    // Leave space above the series and keep count-axis ticks integral.
    final minimum = BigInt.from(money ? 100 : 2);
    final padded = peak + peak ~/ BigInt.from(5);
    final maximum = money
        ? (padded > minimum ? padded : minimum)
        : ((padded > minimum ? padded : minimum) + BigInt.one) ~/
            BigInt.two *
            BigInt.two;
    if (peak == BigInt.zero) {
      final colors = Theme.of(context).colorScheme;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: 210,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.show_chart_rounded, size: 32, color: colors.outline),
                const SizedBox(height: 12),
                Text(ReportStrings.timelineEmpty,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text(
                    '${DateFormat('d. M. yyyy').format(widget.start)} - ${DateFormat('d. M. yyyy').format(widget.end)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ],
            )),
        const Divider(height: 24),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final series in widget.series)
            Text(
                '${series.label}: ${reportChartAmount(BigInt.zero, series.currency ?? widget.currency)}',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      ]);
    }
    final lastActivity = days.lastIndexWhere(
      (day) => widget.series.any(
        (s) => (s.amounts[day] ?? BigInt.zero) > BigInt.zero,
      ),
    );
    final selected = math.min(
      _selected ?? (lastActivity < 0 ? days.length - 1 : lastActivity),
      days.length - 1,
    );
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

    final axisWidth = 54 * MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, constraints) {
      final ticks = _dateTicks(context, widget.start, widget.end,
          math.max(1.0, constraints.maxWidth - axisWidth));
      final style = Theme.of(context).textTheme.bodySmall;
      final layoutKey = (
        constraints.maxWidth,
        style,
        MediaQuery.textScalerOf(context),
        Directionality.of(context),
        Localizations.localeOf(context)
      );
      // Reserve each field's largest size for this data and layout. Hovering
      // changes only its text, so neither wrapping nor the plot position moves.
      // Measure once per data/layout change, rather than on each pointer event.
      if (_legendSizes == null || _legendLayoutKey != layoutKey) {
        _legendLayoutKey = layoutKey;
        final alternatives = [
          days.map((day) => DateFormat('d. M. yyyy').format(day)).toSet(),
          for (var i = 0; i < widget.series.length; i++)
            amounts[i]
                .map((amount) =>
                    '${widget.series[i].label}: ${reportChartAmount(amount, widget.series[i].currency ?? widget.currency)}')
                .toSet(),
        ];
        _legendSizes = [
          for (final values in alternatives)
            _measureLegend(context, values, constraints.maxWidth, style),
        ];
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              SizedBox.fromSize(
                size: _legendSizes![0],
                child: Text(DateFormat('d. M. yyyy').format(days[selected]),
                    style: style),
              ),
              for (var i = 0; i < widget.series.length; i++)
                SizedBox.fromSize(
                  size: _legendSizes![i + 1],
                  child: Text(
                    '${widget.series[i].label}: ${reportChartAmount(amounts[i][selected], widget.series[i].currency ?? widget.currency)}',
                    style: style?.copyWith(color: widget.series[i].color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: axisWidth,
                height: 160,
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
                          height: 160,
                          child: CustomPaint(
                            painter: _TimelinePainter(
                              ticks:
                                  ticks.map((tick) => tick.fraction).toList(),
                              amounts: amounts,
                              maximum: maximum,
                              colors:
                                  widget.series.map((s) => s.color).toList(),
                              grid:
                                  colors.outlineVariant.withValues(alpha: .45),
                              selected: selected,
                              bars: !widget.cumulative &&
                                  widget.series.length == 1,
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
          Padding(
            padding: EdgeInsets.only(left: axisWidth),
            child: SizedBox(
              height: ticks.map((tick) => tick.height).reduce(math.max),
              child: Stack(children: [
                for (final tick in ticks)
                  Positioned(
                    left: tick.left,
                    width: tick.width,
                    child: Text(tick.label,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
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
    });
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
  final List<double> ticks;
  final List<List<BigInt>> amounts;
  final BigInt maximum;
  final List<Color> colors;
  final Color grid;
  final int? selected;
  final bool bars;
  _TimelinePainter({
    required this.ticks,
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
      if (!bars) {
        if (amounts.length == 1 && values.length > 1) {
          final area = Path.from(path)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close();
          canvas.drawPath(
              area,
              Paint()
                ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors[s].withValues(alpha: .12),
                    colors[s].withValues(alpha: .015)
                  ],
                ).createShader(Offset.zero & size));
        }
        canvas.drawPath(path, paint);
      }
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
