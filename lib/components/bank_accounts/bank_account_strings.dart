import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class BankAccountStrings {
  static String get errorTitle => 'BankAccount.errorTitle'.tr();
  static String get tokenVerifying => 'BankAccount.tokenVerifying'.tr();
  static String get tokenVerificationWait =>
      'BankAccount.tokenVerificationWait'.tr();
  static String get tokenAwaitingActivation =>
      'BankAccount.tokenAwaitingActivation'.tr();
  static String get tokenSavedNeedsVerification =>
      'BankAccount.tokenSavedNeedsVerification'.tr();
  static String get linkedAccountIdentity =>
      'BankAccount.linkedAccountIdentity'.tr();
  static String get detailsSyncPending => 'BankAccount.detailsSyncPending'.tr();
  static String syncError(String? code) =>
      (code == 'fio_token_invalid_or_inactive'
              ? 'BankAccount.fioTokenInactive'
              : code == 'fio_receiving_account_mismatch'
                  ? 'BankAccount.fioAccountMismatch'
                  : 'BankAccount.syncRetryRequired')
          .tr();
  static String get tokenSavedNeedsAuthorization =>
      'BankAccount.tokenSavedNeedsAuthorization'.tr();
  static String connectionStatus(String state) =>
      'BankAccount.syncState.$state'.tr();
  static String get connectEmail => 'BankAccount.connect_email'.tr();
  static String get connectionState => 'BankAccount.connection_state'.tr();
  static String get bankPull => 'BankAccount.bank_pull'.tr();
  static String get receiverCommit => 'BankAccount.receiver_commit'.tr();
  static String get notReceived => 'BankAccount.not_received'.tr();
  static String get emailIdentityNotice =>
      'BankAccount.email_identity_notice'.tr();

  static String get bankAccountSettingsTitle =>
      'BankAccount.settingsTitle'.tr();
  static String get generalTab => 'BankAccount.generalTab'.tr();
  static String get fioTokenTab => 'BankAccount.fioTokenTab'.tr();
  static String get usersTab => 'BankAccount.usersTab'.tr();
  static String get bankConnectionTab => 'BankAccount.bankConnectionTab'.tr();

  static String get typeLabel => 'BankAccount.typeLabel'.tr();
  static String get typeFio => 'BankAccount.typeFio'.tr();
  static String get typeGeneral => 'BankAccount.typeGeneral'.tr();

  static String get titleLabel => CommonStrings.title;
  static String get creditorNameLabel => 'BankAccount.creditorNameLabel'.tr();
  static String get creditorNameHelp => 'BankAccount.creditorNameHelp'.tr();
  static String get accountNumberLabel => 'BankAccount.accountNumberLabel'.tr();

  static String get inputModeSplit => 'BankAccount.inputModeSplit'.tr();
  static String get inputModeIban => 'BankAccount.inputModeIban'.tr();
  static String get fullFormatLabel => 'BankAccount.fullFormatLabel'.tr();
  static String get prefixLabel => 'BankAccount.prefixLabel'.tr();
  static String get bankCodeLabel => 'BankAccount.bankCodeLabel'.tr();
  static String get ibanValidationHelp => 'BankAccount.ibanValidationHelp'.tr();

  static String get saveChanges => CommonStrings.save;

  static String get fioTokenInstruction =>
      'BankAccount.fioTokenInstruction'.tr();
  static String get fioTokenLabel => 'BankAccount.fioTokenLabel'.tr();
  static String get fioTokenHint => 'BankAccount.fioTokenHint'.tr();
  static String get updateToken => 'BankAccount.updateToken'.tr();
  static String get tokenUpdated => 'BankAccount.tokenUpdated'.tr();
  static String get tokenExpiryDateLabel =>
      'BankAccount.tokenValidUntilLabel'.tr();
  static String get tokenMaskedInfo => 'BankAccount.tokenMaskedInfo'.tr();
  static String get setDate => 'BankAccount.setDate'.tr();

  static String get addUser => 'BankAccount.addUser'.tr();
  static String get userEmailLabel => 'BankAccount.userEmailLabel'.tr();
  static String get isAdminLabel => 'BankAccount.isAdminLabel'.tr();
  static String get isSupportLabel => 'BankAccount.isSupportLabel'.tr();
  static String get checkAdminInfo => 'BankAccount.checkAdminInfo'.tr();

  static String get cancel => 'BankAccount.cancel'.tr();
  static String get add => CommonStrings.add;
  static String get save => CommonStrings.save;
  static String get editRole => 'BankAccount.editRole'.tr();

  static String get createNewAccount => 'BankAccount.createNewAccount'.tr();
  static String get linkExistingAccount =>
      'BankAccount.linkExistingAccount'.tr();
  static String get selectAccount => 'BankAccount.selectAccount'.tr();
  static String get addBankAccount => 'BankAccount.addBankAccount'.tr();
  static String get untitled => 'BankAccount.untitled'.tr();

  static String get errorSavingToken => 'BankAccount.errorSavingToken'.tr();
  static String get errorUpdatingUser => 'BankAccount.errorUpdatingUser'.tr();
  static String get accountNumberExists =>
      'BankAccount.accountNumberExists'.tr();
  static String get errorRemovingUser => 'BankAccount.errorRemovingUser'.tr();
  static String get priority => 'BankAccount.priority'.tr();
  static String get priorityTooltip => 'BankAccount.priorityTooltip'.tr();
  static String get priorityHelpTitle => priority;
  static String get priorityHelpContent =>
      'BankAccount.priorityHelpContent'.tr();
  static String get bankAccount => 'BankAccount.bankAccount'.tr();
  static String get supportedCurrencies =>
      'BankAccount.supportedCurrencies'.tr();
  static String get addCurrency => 'BankAccount.addCurrency'.tr();
  static String get invalidCurrencyCode =>
      'BankAccount.invalidCurrencyCode'.tr();
  static String get description => 'BankAccount.description'.tr();
  static String get leaveEmptyToKeepToken =>
      'BankAccount.leaveEmptyToKeepToken'.tr();
  static String get currencyCodeLabel => 'BankAccount.currencyCodeLabel'.tr();
  static String get currencyHint => 'BankAccount.currencyHint'.tr();
  static String get adminInfoText => 'BankAccount.adminInfoText'.tr();
  static String get addUserExplanation => 'BankAccount.addUserExplanation'.tr();
  static String get humanReadableLabel => 'BankAccount.humanReadableLabel'.tr();
  static String get humanReadableHelper =>
      'BankAccount.humanReadableHelper'.tr();
  static String get usedIn => 'BankAccount.usedIn'.tr();
  static String get bankAccountsTitle => 'BankAccount.bankAccountsTitle'.tr();
  static String get manageInSettings => 'BankAccount.manageInSettings'.tr();
  static String get lastFioFetchTime => 'BankAccount.lastFioFetchTime'.tr();
  static String get fioFetchNever => 'BankAccount.fioFetchNever'.tr();
  static String get lastFetchTime => 'BankAccount.lastFetchTime'.tr();
  static String get noMoreUsersToAdd => 'BankAccount.noMoreUsersToAdd'.tr();
  static String get addInSettings => 'BankAccount.addInSettings'.tr();
  static String primaryAccountFor(String currency) =>
      'BankAccount.primaryAccountFor'.tr(args: [currency]);
  static String backupAccountFor(String currency) =>
      'BankAccount.backupAccountFor'.tr(args: [currency]);
  static String get removeAccountConfirmation =>
      'BankAccount.removeAccountConfirmation'.tr();
  static String get deleteAccountTitle => 'BankAccount.deleteAccountTitle'.tr();
  static String missingAccountForCurrencies(String currencies) =>
      'BankAccount.missingAccountForCurrencies'.tr(args: [currencies]);
  static String get addAccountForPayments =>
      'BankAccount.addAccountForPayments'.tr();
  static String get askManagerForPaymentAccount =>
      'BankAccount.askManagerForPaymentAccount'.tr();
  static String get manageInUnitSettings =>
      'BankAccount.manageInUnitSettings'.tr();

  static String get unlink => 'BankAccount.unlink'.tr();
  static String get unlinkConfirmationTitle =>
      'BankAccount.unlinkConfirmationTitle'.tr();
  static String get unlinkConfirmationMessage =>
      'BankAccount.unlinkConfirmationMessage'.tr();
  static String get unlinkDependencyWarningTitle =>
      'BankAccount.unlinkDependencyWarningTitle'.tr();
  static String get unlinkDependencyMessage =>
      'BankAccount.unlinkDependencyMessage'.tr();
  static String get unlinkDependencyConsequence =>
      'BankAccount.unlinkDependencyConsequence'.tr();
  static String get unlinkAnyway => 'BankAccount.unlinkAnyway'.tr();

  // Sync / Email Import
  static String get syncTab => 'BankAccount.syncTab'.tr();
  static String get syncInstruction => 'BankAccount.syncInstruction'.tr();
  static String get emailSecurityNote => 'BankAccount.emailSecurityNote'.tr();
  static String get maskedEmailExplanation =>
      'BankAccount.maskedEmailExplanation'.tr();

  static String get setupGuideTitle => 'BankAccount.setupGuide.title'.tr();
  static String get setupGuideStep1 => 'BankAccount.setupGuide.step1'.tr();
  static String get setupGuideStep2 => 'BankAccount.setupGuide.step2'.tr();
  static String get setupGuideStep3 => 'BankAccount.setupGuide.step3'.tr();
  static String get setupGuideStep4 => 'BankAccount.setupGuide.step4'.tr();
  static String get setupGuideStep5 => 'BankAccount.setupGuide.step5'.tr();

  static String get setupGuideExplanationTitle =>
      'BankAccount.setupGuide.explanationTitle'.tr();
  static String get setupGuideExplanationSet =>
      'BankAccount.setupGuide.explanationSet'.tr();
  static String get setupGuideExplanationNotSet =>
      'BankAccount.setupGuide.explanationNotSet'.tr();
  static String get setupGuideExplanationFioNote =>
      'BankAccount.setupGuide.explanationFioNote'.tr();

  static String get fioSetupGuideTitle =>
      'BankAccount.fioSetupGuide.title'.tr();
  static String get fioSetupGuideStep1 =>
      'BankAccount.fioSetupGuide.step1'.tr();
  static String get fioSetupGuideStep2 =>
      'BankAccount.fioSetupGuide.step2'.tr();
  static String get fioSetupGuideStep3 =>
      'BankAccount.fioSetupGuide.step3'.tr();

  static String get forwardingEmailLabel =>
      'BankAccount.forwardingEmailLabel'.tr();
  static String get copyEmail => 'BankAccount.copyEmail'.tr();
  static String get regenerateToken => 'BankAccount.regenerateToken'.tr();
  static String get regenerateTokenConfirmation =>
      'BankAccount.regenerateTokenConfirmation'.tr();

  static String get setupConnectionNow => 'BankAccount.setupConnectionNow'.tr();
}
