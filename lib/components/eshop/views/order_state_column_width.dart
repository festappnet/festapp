import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import '../models/order_model.dart';

/// Size against the actual localized labels and each row's visible indicators.
/// A large manual width is preserved by the caller; this is the minimum needed.
double orderStateColumnWidth(
    BuildContext context, Iterable<OrderModel> orders) {
  var width = 140.0;
  final style = DefaultTextStyle.of(context)
      .style
      .merge(TrinaGridStyleConfig.defaultLightCellTextStyle);
  for (final order in orders) {
    final label = OrderModel.statesDataGridToUpper(order.stateLabel);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final indicators = (order.bankSyncWarning == null ? 0 : 28) +
        (order.state == OrderModel.expiredState ? 24 : 0);
    width = math.max(width, painter.width + 16 + indicators);
    painter.dispose();
  }
  return width.ceilToDouble();
}
