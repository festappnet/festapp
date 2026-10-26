import 'package:easy_localization/easy_localization.dart';

class TicketBatchStrings {
  static String text(String key) => 'TicketBatches.$key'.tr();
  static String selectedCount(int count) =>
      'TicketBatches.selectedCount'.tr(namedArgs: {'count': '$count'});
  static String get title => text('title');
  static String get create => text('create');
  static String get available => text('available');
  static String get sold => text('sold');
  static String get voided => text('voided');
}
