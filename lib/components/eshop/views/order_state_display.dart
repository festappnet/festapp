import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// A reusable widget to display a single order state or a from-to state transition.
class OrderStateDisplay extends StatelessWidget {
  /// The formatted string representing the state.
  /// - For a single state: `"key;STATE_TEXT"`
  /// - For a transition: `"key1;STATE1_TEXT → key2;STATE2_TEXT"`
  final String formattedState;

  /// A function to get the background color for a state key.
  final Color Function(String) getBackground;

  /// An optional fixed width for the state tags when in a transition view.
  ///
  /// Providing this value ensures both 'from' and 'to' tags have the same
  /// width for a clean, stable UI.
  final double? stateTagWidth;

  /// If true, the widget will wrap to a `Column` on smaller screens.
  /// Defaults to `false`.
  final bool enableWrapping;

  const OrderStateDisplay({
    super.key,
    required this.formattedState,
    required this.getBackground,
    this.stateTagWidth,
    this.enableWrapping = false,
  });

  /// A helper method to calculate the optimal width for the state tags.
  static double _calculateOptimalWidth({
    required BuildContext context,
    required List<String> stateLabels,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  }) {
    final textStyle = DefaultTextStyle.of(context).style;
    double maxWidth = 0;

    for (final label in stateLabels) {
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        maxLines: 1,
        textDirection: ui.TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(minWidth: 0, maxWidth: double.infinity);

      final totalWidth = textPainter.size.width + padding.horizontal;
      textPainter.dispose();

      if (totalWidth > maxWidth) {
        maxWidth = totalWidth;
      }
    }
    return maxWidth;
  }

  Widget _buildStateTag(String formattedStateValue, {double? fixedWidth}) {
    if (!formattedStateValue.contains(';')) return const SizedBox.shrink();
    final parts = formattedStateValue.split(';');
    if (parts.length != 2) return const SizedBox.shrink();

    final key = parts[0];
    final text = parts[1].toUpperCase();

    return SizedBox(
      width: fixedWidth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: getBackground(key),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            text,
            maxLines: enableWrapping ? null : 1,
            textAlign: TextAlign.center,
            overflow: enableWrapping ? null : TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTransition = formattedState.contains("→");

    if (isTransition) {
      final parts = formattedState.split("→");
      final fromState = parts[0].trim();
      final toState = parts[1].trim();

      return LayoutBuilder(
        builder: (context, constraints) {
          const double arrowAndPaddingWidth = 40;
          final tagWidth =
              stateTagWidth ??
              (enableWrapping
                  ? _calculateOptimalWidth(
                      context: context,
                      stateLabels: [
                        fromState.split(';').last.toUpperCase(),
                        toState.split(';').last.toUpperCase(),
                      ],
                    )
                  : 80.0);
          final requiredWidth = tagWidth * 2 + arrowAndPaddingWidth;

          if (enableWrapping && constraints.maxWidth < requiredWidth) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStateTag(fromState),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Icon(Icons.arrow_downward, size: 18),
                ),
                _buildStateTag(toState),
              ],
            );
          } else {
            return Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [_buildStateTag(fromState, fixedWidth: tagWidth)],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [_buildStateTag(toState, fixedWidth: tagWidth)],
                  ),
                ),
              ],
            );
          }
        },
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: _buildStateTag(formattedState),
      );
    }
  }
}
