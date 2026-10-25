import 'dart:async';
import 'package:fstapp/components/html/html_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/form_strings.dart';

class CountdownWidget extends StatefulWidget {
  final DateTime targetTime;
  final VoidCallback onFinished;
  final String? title;
  final bool compact;

  const CountdownWidget({
    super.key,
    required this.targetTime,
    required this.onFinished,
    this.title,
    this.compact = false,
  });

  @override
  _CountdownWidgetState createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  Timer? _timer;
  late Duration _timeLeft;

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft(firstRun: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateTimeLeft();
    });
  }

  void _calculateTimeLeft({bool firstRun = false}) {
    final now = DateTime.now();
    if (widget.targetTime.isBefore(now)) {
      _timer?.cancel();
      widget.onFinished();
      if (firstRun) {
        _timeLeft = Duration.zero;
      } else {
        setState(() {
          _timeLeft = Duration.zero;
        });
      }
    } else {
      if (firstRun) {
        _timeLeft = widget.targetTime.difference(now);
      } else {
        setState(() {
          _timeLeft = widget.targetTime.difference(now);
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 0 : 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                height: widget.compact
                    ? 12
                    : 60), // Add some top spacing so it is not superglued to the top
            if (widget.title != null)
              Padding(
                padding: EdgeInsets.only(bottom: widget.compact ? 8 : 24),
                child: HtmlView(
                  html:
                      "<div style='text-align: center;'>${widget.title!}</div>",
                  fontSize: 24, // Approx headlineMedium size
                  isSelectable: false,
                ),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTimeBlock(context, _timeLeft.inDays, FormStrings.days),
                  const SizedBox(width: 8),
                  _buildTimeBlock(context, _timeLeft.inHours.remainder(24),
                      FormStrings.hours),
                  const SizedBox(width: 8),
                  _buildTimeBlock(context, _timeLeft.inMinutes.remainder(60),
                      FormStrings.minutes),
                  const SizedBox(width: 8),
                  _buildTimeBlock(context, _timeLeft.inSeconds.remainder(60),
                      FormStrings.seconds),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBlock(BuildContext context, int value, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        // Use a very subtle tint of the primary color for background in light mode
        // User requested "very slightly colored" and "solid opaque" background
        color: Color.alphaBlend(primary.withOpacity(isDark ? 0.05 : 0.03),
            isDark ? Colors.grey.shade900 : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 100, // Fixed width to prevent jitter - increased for safety
            child: Text(
              value.toString().padLeft(2, '0'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
