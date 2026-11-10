import 'package:easy_localization/easy_localization.dart';

class SeatingStrings {
  static String text(String key) => 'Seating.$key'.tr();
  static String reason(String key) {
    final lookup = 'Seating.$key';
    return trExists(lookup) ? lookup.tr() : text('UNKNOWN');
  }
}
