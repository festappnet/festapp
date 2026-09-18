import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the scan flows (ticket and entry scanning).
/// Keys live under the "FeatureTicket" namespace in assets/translations/*.json.
class ScanStrings {
  static String get scanCode => 'FeatureTicket.scanCode'.tr(); // "Scan Code"
  static String get enterScanCode =>
      'FeatureTicket.enterScanCode'.tr(); // "Enter Scan Code"
  static String get confirmTicket =>
      'FeatureTicket.confirmTicket'.tr(); // "Confirm Ticket"
  static String get scanCameraInstruction => 'FeatureTicket.scanCameraInstruction'
      .tr(); // "Point the camera at the attendee's code for an entry verification."
  static String get resetPassword =>
      'FeatureTicket.resetPassword'.tr(); // "Reset Password"
  static String get signedInCompanions =>
      'FeatureTicket.signedInCompanions'.tr(); // "Signed in companions"
  static String get startCamera => 'FeatureTicket.startCamera'.tr();
  static String get restartCamera => 'FeatureTicket.restartCamera'.tr();
  static String get cameraStartDescription =>
      'FeatureTicket.cameraStartDescription'.tr();
  static String get cameraUnavailable => 'FeatureTicket.cameraUnavailable'.tr();
}
