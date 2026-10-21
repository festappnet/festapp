import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

/// A one-off acknowledgement after returning from creation, with no extra badge.
class OccasionCreatedHighlight extends StatelessWidget {
  final Widget child;
  const OccasionCreatedHighlight({super.key, required this.child});

  /// Uses the actual sliver layout, including every preceding header/draft grid,
  /// so a newly created card is reachable even before its lazy child is built.
  static Future<void> reveal(
      {required GlobalKey gridKey,
      required ScrollController controller,
      required int index,
      required bool animate}) async {
    final grid = gridKey.currentContext?.findRenderObject();
    if (grid is! RenderSliverGrid || !grid.attached || !controller.hasClients)
      return;
    final layout = grid.gridDelegate.getLayout(grid.constraints);
    final offset = grid.constraints.precedingScrollExtent +
        layout.getGeometryForChildIndex(index).scrollOffset;
    final target =
        offset.clamp(0.0, controller.position.maxScrollExtent).toDouble();
    if (animate) {
      await controller.animateTo(target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    } else {
      controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: reduced ? 1 : 0),
      duration: const Duration(milliseconds: 1800),
      child: child,
      builder: (context, value, child) => Stack(children: [
        child!,
        Positioned.fill(
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: value),
              width: 2),
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: .06 * value),
        )))),
      ]),
    );
  }
}
