import 'package:intl/intl.dart';

import '../models/occasion_report_model.dart';
import '../report_strings.dart';

/// Localized display and export of the same report snapshot, without a new RPC.
String formatReportText(OccasionReport report) {
  final text = StringBuffer()
    ..writeln(report.title)
    ..writeln(report.generatedAt.toUtc().toIso8601String());
  void counts(String title, ReportCounts counts) {
    text.writeln('$title: ${counts.total}');
    for (final entry in counts.states.entries) {
      text.writeln('  ${ReportStrings.state(entry.key)}: ${entry.value}');
    }
  }

  counts(ReportStrings.orders, report.orders);
  if (ReportStrings.hasTickets) counts(ReportStrings.tickets, report.tickets);
  text
    ..writeln(
        '${ReportStrings.spots}: ${report.spotsOccupied} / ${report.spotsTotal}')
    ..writeln('${ReportStrings.free}: ${report.spotsFree}');
  for (final money in report.money) {
    text
      ..writeln()
      ..writeln(money.currency);
    for (final amount in money.amounts.entries) {
      if (money.hasDeposits || !amount.key.contains('deposit')) {
        text.writeln(
            '${ReportStrings.metric(amount.key)}: ${amount.value} ${money.currency}');
      }
    }
  }
  if (report.hasTimeline) {
    text
      ..writeln()
      ..writeln(ReportStrings.orderTimeline)
      ..writeln(ReportStrings.orderTimelineHelp);
    for (final day in report.orderDays) {
      text.writeln(
          '${DateFormat('d. M. yyyy').format(day.day)} ${day.currency}: ${day.count}');
    }
    text
      ..writeln()
      ..writeln(ReportStrings.paymentTimeline)
      ..writeln(ReportStrings.paymentTimelineHelp);
    for (final day in report.paymentDays) {
      text.writeln(
          '${DateFormat('d. M. yyyy').format(day.day)} ${day.currency}: ${ReportStrings.received} ${day.received}, ${ReportStrings.returned} ${day.returned}');
    }
  }
  text
    ..writeln()
    ..writeln(ReportStrings.products)
    ..writeln(ReportStrings.productsHelp);
  for (final product in report.products) {
    text.writeln(
        '${product.typeTitle ?? ReportStrings.noType} / ${product.title}: ${product.count}');
  }
  text
    ..writeln()
    ..writeln(ReportStrings.statesHelp)
    ..writeln(ReportStrings.spotsHelp)
    ..writeln(ReportStrings.moneyHelp)
    ..writeln(ReportStrings.moneyDetails);
  for (final warning in report.warnings.entries) {
    text.writeln('${ReportStrings.metric(warning.key)} (${warning.value})');
  }
  return text.toString();
}
