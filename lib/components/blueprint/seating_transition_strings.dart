import 'package:easy_localization/easy_localization.dart';

class SeatingTransitionStrings {
  static String text(String key) => 'SeatingTransition.$key'.tr();
  static String reason(String key) {
    final lookup = 'SeatingTransition.$key';
    return trExists(lookup) ? lookup.tr() : text('UNKNOWN');
  }
}
