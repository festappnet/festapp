import 'package:easy_localization/easy_localization.dart';

class ClientChangesStrings {
  static String get title => 'ClientChanges.title'.tr();
  static String get onlineOnly => 'ClientChanges.onlineOnly'.tr();
  static String empty(int days) =>
      'ClientChanges.empty'.tr(namedArgs: {'days': '$days'});
  static String get notActive => 'ClientChanges.notActive'.tr();
  static String get retry => 'ClientChanges.retry'.tr();
  static String get loadError => 'ClientChanges.loadError'.tr();
  static String subtitle(int days) =>
      'ClientChanges.subtitle'.tr(namedArgs: {'days': '$days'});
  static String rangeDays(int days) =>
      'ClientChanges.rangeDays'.tr(namedArgs: {'days': '$days'});
  static String totalChanges(int count) =>
      'ClientChanges.totalChanges'.tr(namedArgs: {'count': '$count'});
  static String dayChanges(String day, int count) =>
      'ClientChanges.dayChanges'.tr(namedArgs: {
        'day': day,
        'count': '$count',
      });
}
