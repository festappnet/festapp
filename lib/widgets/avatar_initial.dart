import 'package:material_ui/material_ui.dart';

/// Centers capitals by their configured face's cap height, keeping native text
/// layout responsible for the actual baseline (including font loading/scaling).
class AvatarInitial extends StatelessWidget {
  const AvatarInitial({
    super.key,
    required this.initial,
    required this.style,
    required this.capHeightRatio,
  });

  final String initial;
  final TextStyle style;
  final double? capHeightRatio;

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final text = Text(
      initial,
      style: resolved,
      textScaler: scaler,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = capHeightRatio;
        if (ratio == null || !constraints.hasBoundedHeight) {
          return Center(child: text);
        }
        return Align(
          alignment: Alignment.topCenter,
          child: Baseline(
            baseline:
                (constraints.maxHeight +
                    scaler.scale(resolved.fontSize!) * ratio) /
                2,
            baselineType: TextBaseline.alphabetic,
            child: text,
          ),
        );
      },
    );
  }
}
