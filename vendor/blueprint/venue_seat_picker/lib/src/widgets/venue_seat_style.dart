import 'package:flutter/material.dart';

import '../model/seat_status.dart';

/// Visual tokens used by the default venue seat renderer.
@immutable
class VenueSeatThemeData {
  const VenueSeatThemeData({
    this.available = const Color(0xff2e7d32),
    this.selected = const Color(0xff2e7d32),
    this.held = const Color(0x42000000),
    this.booked = const Color(0x1f000000),
    this.checkedIn = const Color(0xff1976d2),
    this.blocked = const Color(0xdd000000),
    this.selectionBorder = Colors.orange,
    this.highlightBorder,
    this.checkColor = Colors.white,
    this.bookedMarkColor = Colors.black,
  });

  final Color available;
  final Color selected;
  final Color held;
  final Color booked;
  final Color checkedIn;
  final Color blocked;
  final Color selectionBorder;
  final Color? highlightBorder;
  final Color checkColor;
  final Color bookedMarkColor;

  Color colorFor(SeatStatus status) => switch (status) {
    SeatStatus.available => available,
    SeatStatus.held => held,
    SeatStatus.booked => booked,
    SeatStatus.checkedIn => checkedIn,
    SeatStatus.blocked => blocked,
  };
}

/// Shared viewport and surface configuration for venue seat widgets.
@immutable
class VenueSeatViewConfig {
  const VenueSeatViewConfig({
    this.maxScale = 5,
    this.boundaryMargin = EdgeInsets.zero,
    this.backgroundColor = Colors.white,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.theme = const VenueSeatThemeData(),
  }) : assert(maxScale > 0);

  /// Creates a config whose surface follows the host light or dark theme.
  factory VenueSeatViewConfig.fromTheme(
    BuildContext context, {
    double maxScale = 5,
    EdgeInsets boundaryMargin = EdgeInsets.zero,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
    VenueSeatThemeData theme = const VenueSeatThemeData(),
  }) => VenueSeatViewConfig(
    maxScale: maxScale,
    boundaryMargin: boundaryMargin,
    backgroundColor: Theme.of(context).colorScheme.surface,
    borderRadius: borderRadius,
    theme: theme,
  );

  final double maxScale;

  /// Extra scene-space pan allowance. Finite margins keep the plan visible;
  /// an all-infinite margin explicitly enables unrestricted panning.
  final EdgeInsets boundaryMargin;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final VenueSeatThemeData theme;
}
