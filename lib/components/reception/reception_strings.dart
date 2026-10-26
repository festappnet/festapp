import 'package:festapp_core/forms.dart';
import 'package:easy_localization/easy_localization.dart';

class ReceptionStrings {
  static String get title => 'Reception.title'.tr();
  static String get subtitle => 'Reception.subtitle'.tr();
  static String get create => 'Reception.create'.tr();
  static String get group => 'Reception.group'.tr();
  static String get accommodation => 'Reception.accommodation'.tr();
  static String get none => 'Reception.none'.tr();
  static String get unspecified => 'Reception.unspecified'.tr();
  static String get duplicateWarning => 'Reception.duplicateWarning'.tr();
  static String get confirmDifferent => 'Reception.confirmDifferent'.tr();
  static String get rotate => 'Reception.rotate'.tr();
  static String get cancel => 'Reception.cancel'.tr();
  static String get cancelWarning => 'Reception.cancelWarning'.tr();
  static String get used => 'Reception.used'.tr();
  static String get unused => 'Reception.unused'.tr();
  static String get scan => 'Reception.scan'.tr();
  static String get invalidQr => 'Reception.invalidQr'.tr();
  static String get cameraUnavailable => 'Reception.cameraUnavailable'.tr();
  static String get accessDenied => 'Reception.accessDenied'.tr();
  static String get yes => 'Reception.yes'.tr();
  static String get no => 'Reception.no'.tr();
  static String get issueQr => 'Reception.issueQr'.tr();
  static String get signingIn => 'Reception.signingIn'.tr();
  static String get verifyingQr => 'Reception.verifyingQr'.tr();
  static String get signedIn => 'Reception.signedIn'.tr();
  static String get openingApp => 'Reception.openingApp'.tr();
  static String get enterManualCode => 'Reception.enterManualCode'.tr();
  static String get manualCode => 'Reception.manualCode'.tr();
  static String get manualCodeValidity => 'Reception.manualCodeValidity'.tr();
  static String get findParticipant => 'Reception.findParticipant'.tr();
  static String get searchParticipant => 'Reception.searchParticipant'.tr();
  static String get noParticipantsFound => 'Reception.noParticipantsFound'.tr();

  static String commandError(ReceptionCommandError error) => switch (error) {
        ReceptionCommandError.emailAlreadyExists =>
          'Reception.emailAlreadyExists'.tr(),
        ReceptionCommandError.commandConflict =>
          'Reception.commandConflict'.tr(),
        ReceptionCommandError.rateLimited => 'Reception.rateLimited'.tr(),
        ReceptionCommandError.receptionUnavailable =>
          'Reception.receptionUnavailable'.tr(),
        ReceptionCommandError.registrationUnavailable =>
          'Reception.registrationUnavailable'.tr(),
        ReceptionCommandError.invalidInput => 'Reception.invalidInput'.tr(),
        ReceptionCommandError.unexpected =>
          'Reception.unexpectedCommandError'.tr(),
      };
}
