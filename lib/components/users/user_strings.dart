import 'package:easy_localization/easy_localization.dart';

class UserStrings {
  static String get googlePasswordVisibility =>
      'FeatureUser.googlePasswordVisibility'.tr();
  static String get googleUnlinkProof => 'FeatureUser.googleUnlinkProof'.tr();
  static String get googleTerms => 'FeatureUser.googleTerms'.tr();
  static String get googlePrivacy => 'FeatureUser.googlePrivacy'.tr();
  static String get googleContinue => 'FeatureUser.googleContinue'.tr();
  static String get googleSubtitle => 'FeatureUser.googleSubtitle'.tr();
  static String get googleOr => 'FeatureUser.googleOr'.tr();
  static String get googleClose => 'FeatureUser.googleClose'.tr();
  static String get googleOpening => 'FeatureUser.googleOpening'.tr();
  static String get googleCompleting => 'FeatureUser.googleCompleting'.tr();
  static String get googleProof => 'FeatureUser.googleProof'.tr();
  static String get googleLink => 'FeatureUser.googleLink'.tr();
  static String get googleProfile => 'FeatureUser.googleProfile'.tr();
  static String get googleConsent => 'FeatureUser.googleConsent'.tr();
  static String get googleCreate => 'FeatureUser.googleCreate'.tr();
  static String get googleRetry => 'FeatureUser.googleRetry'.tr();
  static String get googleCancelled => 'FeatureUser.googleCancelled'.tr();
  static String get googleExpired => 'FeatureUser.googleExpired'.tr();
  static String get googleError => 'FeatureUser.googleError'.tr();
  static String get googleProofError => 'FeatureUser.googleProofError'.tr();
  static String get googleLeaveDraft => 'FeatureUser.googleLeaveDraft'.tr();
  static String get googleMailbox => 'FeatureUser.googleMailbox'.tr();
  static String get googleSendCode => 'FeatureUser.googleSendCode'.tr();
  static String get googleVerifyCode => 'FeatureUser.googleVerifyCode'.tr();
  static String get googleCode => 'FeatureUser.googleCode'.tr();
  static String get googleUnlink => 'FeatureUser.googleUnlink'.tr();
  static String get googleMfa => 'FeatureUser.googleMfa'.tr();

  static String get receptionist => 'UserColumns.receptionist'.tr();
  // Column Titles
  static String get id => 'UserColumns.id'.tr();
  static String get unit => 'UserColumns.unit'.tr();
  static String get email => 'UserColumns.email'.tr();
  static String get name => 'UserColumns.name'.tr();
  static String get surname => 'UserColumns.surname'.tr();
  static String get group => 'UserColumns.group'.tr();
  static String get sex => 'UserColumns.sex'.tr();
  static String get accommodation => 'UserColumns.accommodation'.tr();
  static String get phone => 'UserColumns.phone'.tr();
  static String get birthday => 'UserColumns.birthday'.tr();
  static String get role => 'UserColumns.role'.tr();
  static String get text1 => 'UserColumns.text1'.tr();
  static String get text2 => 'UserColumns.text2'.tr();
  static String get text3 => 'UserColumns.text3'.tr();
  static String get note => 'UserColumns.note'.tr();
  static String get diet => 'UserColumns.diet'.tr();
  static String get form => 'UserColumns.form'.tr();
  static String get orderedAt => 'UserColumns.orderedAt'.tr();
  static String get createdAt => 'UserColumns.createdAt'.tr();
  static String get lastSignInAt => 'UserColumns.lastSignInAt'.tr();

  // Status/Right Column Titles
  static String get volunteer => 'UserColumns.volunteer'.tr();
  static String get administrator => 'UserColumns.administrator'.tr();
  static String get editor => 'UserColumns.editor'.tr();
  static String get readOnly => 'UserColumns.readOnly'.tr();
  static String get editOrders => 'UserColumns.editOrders'.tr();
  static String get readOrders => 'UserColumns.readOrders'.tr();
  static String get cleaningCrew => 'UserColumns.cleaningCrew'.tr();
  static String get cleaningBlocked => 'UserColumns.cleaningBlocked'.tr();
  static String get approver => 'UserColumns.approver'.tr();
  static String get approved => 'UserColumns.approved'.tr();
  static String get invited => 'UserColumns.invited'.tr();

  // Role and status column help
  static String get administratorHelp => 'UserColumns.administratorHelp'.tr();
  static String get editorHelp => 'UserColumns.editorHelp'.tr();
  static String get readOnlyHelp => 'UserColumns.readOnlyHelp'.tr();
  static String get editOrdersHelp => 'UserColumns.editOrdersHelp'.tr();
  static String get readOrdersHelp => 'UserColumns.readOrdersHelp'.tr();
  static String get unitAdministratorHelp =>
      'UserColumns.unitAdministratorHelp'.tr();
  static String get unitEditorHelp => 'UserColumns.unitEditorHelp'.tr();
  static String get unitReadOnlyHelp => 'UserColumns.unitReadOnlyHelp'.tr();
  static String get approverHelp => 'UserColumns.approverHelp'.tr();
  static String get approvedHelp => 'UserColumns.approvedHelp'.tr();
  static String get receptionistHelp => 'UserColumns.receptionistHelp'.tr();
  static String get cleaningCrewHelp => 'UserColumns.cleaningCrewHelp'.tr();
  static String get cleaningBlockedHelp =>
      'UserColumns.cleaningBlockedHelp'.tr();
  static String get volunteerHelp => 'UserColumns.volunteerHelp'.tr();
  static String get invitedHelp => 'UserColumns.invitedHelp'.tr();

  // FeatureUser
  static String get signIn => 'FeatureUser.signIn'.tr();
  static String get signOut => 'FeatureUser.signOut'.tr();
  static String get companionSignIn => 'FeatureUser.companionSignIn'.tr();
  static String get companionSignOut => 'FeatureUser.companionSignOut'.tr();
  static String get emailLabel => 'FeatureUser.email'.tr();
  static String get password => 'FeatureUser.password'.tr();
  static String get confirmPassword => 'FeatureUser.confirmPassword'.tr();
  static String get passwordsDoNotMatch =>
      'FeatureUser.passwordsDoNotMatch'.tr();
  static String get passwordMinLength => 'FeatureUser.passwordMinLength'.tr();
  static String get fillPassword => 'FeatureUser.fillPassword'.tr();
  static String get signInSuccess => 'FeatureUser.signInSuccess'.tr();
  static String get invalidCredentials => 'FeatureUser.invalidCredentials'.tr();
  static String get createAPassword => 'FeatureUser.createAPassword'.tr();
  static String get newPassword => 'FeatureUser.newPassword'.tr();
  static String get changePassword => 'FeatureUser.changePassword'.tr();
  static String get forgotPassword => 'FeatureUser.forgotPassword'.tr();
  static String get credentialsSent => 'FeatureUser.credentialsSent'.tr();
  static String get passwordResetSent => 'FeatureUser.passwordResetSent'.tr();
  static String get enterEmailReset => 'FeatureUser.enterEmailReset'.tr();
  static String get registrationFailed => 'FeatureUser.registrationFailed'.tr();
  static String Function(String email) get emailInUse =>
      (email) => 'FeatureUser.emailInUse'.tr(namedArgs: {"email": email});
  static String get passwordChanged => 'FeatureUser.passwordChanged'.tr();
  static String get passwordChangedSignInRequired =>
      'FeatureUser.passwordChangedSignInRequired'.tr();
  static String get passwordChangeFailedGeneric =>
      'FeatureUser.passwordChangeFailedGeneric'.tr();
  static String get tokenInvalid => 'FeatureUser.tokenInvalid'.tr();
  static String get firstTime => 'FeatureUser.firstTime'.tr();
  static String get signUp => 'FeatureUser.signUp'.tr();
  static String get registrationAlmostComplete =>
      'FeatureUser.registrationAlmostComplete'.tr();
  static String get passwordOrCode => 'FeatureUser.passwordOrCode'.tr();
  static String Function(String email) get credentialsSentLong => (email) =>
      'FeatureUser.credentialsSentLong'.tr(namedArgs: {"email": email});
  static String get clickToSignIn => 'FeatureUser.clickToSignIn'.tr();
  static String get accountRequiredToJoin =>
      'FeatureUser.accountRequiredToJoin'.tr();
  static String get resetPassword => 'FeatureUser.resetPassword'.tr();
  static String get forgotPasswordQuestion =>
      'FeatureUser.forgotPasswordQuestion'.tr();
  static String get forgotYourPassword => 'FeatureUser.forgotYourPassword'.tr();
  static String get sendResetEmail => 'FeatureUser.sendResetEmail'.tr();
  static String get existingAccountRecoveryHelp =>
      'FeatureUser.existingAccountRecoveryHelp'.tr();
  static String get changePasswordTitle =>
      'FeatureUser.changePasswordTitle'.tr();
  static String get createPasswordToContinue =>
      'FeatureUser.createPasswordToContinue'.tr();
  static String get iAm => 'FeatureUser.iAm'.tr();
  static String get addEvent => 'FeatureUser.addEvent'.tr();
  static String get myEvents => 'FeatureUser.myEvents'.tr();
  static String get admin => 'FeatureUser.admin'.tr(); // "Admin"
  static String get profile => 'FeatureUser.profile'.tr(); // "Profile"
  static String get invite => 'FeatureUser.invite'.tr(); // "Invite"
  static String get inviteInfo => 'FeatureUser.inviteInfo'
      .tr(); // "Users will get a sign-in code via e-mail."
  static String get reinviteConfirm => 'FeatureUser.reinviteConfirm'
      .tr(); // "Some users have already been invited. Do you want to invite them again and send a new sign-in code?"
  static String invitedUser({required String user}) => 'FeatureUser.invitedUser'
      .tr(namedArgs: {'user': user}); // "Invited: {user}."
  static String inviteFailed({required String user, required String retries}) =>
      'FeatureUser.inviteFailed'.tr(namedArgs: {
        'user': user,
        'retries': retries
      }); // "Failed to invite {user}. Number of retries: ({retries})."
  static String invitationStatusFailed({required String user}) =>
      'FeatureUser.invitationStatusFailed'.tr(namedArgs: {'user': user});
  static String get sendAppLinks => 'FeatureUser.sendAppLinks'.tr();
  static String get sendAppLinksInfo => 'FeatureUser.sendAppLinksInfo'.tr();
  static String get resendAppLinksConfirm =>
      'FeatureUser.resendAppLinksConfirm'.tr();
  static String get appLinksSent => 'FeatureUser.appLinksSent'.tr();
  static String appLinksSentUser({required String user}) =>
      'FeatureUser.appLinksSentUser'.tr(namedArgs: {'user': user});
  static String sendAppLinksFailed(
          {required String user, required String retries}) =>
      'FeatureUser.sendAppLinksFailed'.tr(namedArgs: {
        'user': user,
        'retries': retries,
      });
  static String appLinksStatusFailed({required String user}) =>
      'FeatureUser.appLinksStatusFailed'.tr(namedArgs: {'user': user});
  static String passwordChangeFailed(
          {required String user, required String error}) =>
      'FeatureUser.passwordChangeFailed'.tr(namedArgs: {
        'user': user,
        'error': error
      }); // "Failed for user {user}: {error}"
  static String get changePasswordInstructions =>
      'FeatureUser.changePasswordInstructions'
          .tr(); // "Change Password Instructions"
  static String get resetPasswordProceedConfirm =>
      'FeatureUser.resetPasswordProceedConfirm'
          .tr(); // "You'll receive an email with a link to reset your password. Do you want to proceed?"
  static String passwordResetLinkSent({required String email}) =>
      'FeatureUser.passwordResetLinkSent'.tr(namedArgs: {
        'email': email
      }); // "A password reset link has been sent to {email}. Please check your inbox and follow the instructions to reset your password."
  static String get passwordResetFailed =>
      'FeatureUser.passwordResetFailed'.tr();
  static String get passwordResetEmailMissing =>
      'FeatureUser.passwordResetEmailMissing'.tr();
  static String get insertHere => 'FeatureUser.insertHere'.tr(); // "Input here"
  static String get deleteAccount =>
      'FeatureUser.deleteAccount'.tr(); // "Delete account"
  static String get deleteAccountScope => 'FeatureUser.deleteAccountScope'.tr();
  static String get deleteAccountConfirm =>
      'FeatureUser.deleteAccountConfirm'.tr();
  static String accountDeletionEmailSent(String email) =>
      'FeatureUser.accountDeletionEmailSent'.tr(namedArgs: {'email': email});
  static String get accountDeletionFailed =>
      'FeatureUser.accountDeletionFailed'.tr();
  static String get privacy => 'FeatureUser.privacy'.tr();
  static String get privacyChoices => 'FeatureUser.privacyChoices'.tr();
  static String get terms => 'FeatureUser.terms'.tr();
  static String get support => 'FeatureUser.support'.tr();
  static String get signupLegalNotice =>
      'FeatureUser.signupLegalNotice'.tr(namedArgs: {'button': signUp});
  static String get signupTerms => 'FeatureUser.signupTerms'.tr();
  static String get signupPrivacy => 'FeatureUser.signupPrivacy'.tr();
  static String get signupPrivacyNotice =>
      'FeatureUser.signupPrivacyNotice'.tr();
  static String get showMyCode =>
      'FeatureUser.showMyCode'.tr(); // "Show my code"
  static String get showCode => 'FeatureUser.showCode'.tr(); // "Show Code"
  static String signedInEvents({required String count}) =>
      'FeatureUser.signedInEvents'
          .tr(namedArgs: {'count': count}); // "Signed in events: {count}"
  static String welcomeIn({required String name}) => 'FeatureUser.welcomeIn'
      .tr(namedArgs: {'name': name}); // "Welcome in {name}!"

  // Companions
  static String get companionName =>
      'FeatureUser.companionName'.tr(); // "Companion Name"
  static String get companionOf =>
      'FeatureUser.companionOf'.tr(); // "Companion of"
  static String companionManagedBy(String name) =>
      'FeatureUser.companionManagedBy'.tr(namedArgs: {'name': name});
  static String companionManages(String names) =>
      'FeatureUser.companionManages'.tr(namedArgs: {'names': names});
  static String get createCompanion =>
      'FeatureUser.createCompanion'.tr(); // "Create Companion"
  static String companionInfo({required String maxCompanions}) =>
      'FeatureUser.companionInfo'.tr(namedArgs: {
        'max_companions': maxCompanions
      }); // "If you have a child, partner or friend without a phone, you can sign them in as a companion. They will need a festival band to enter the event. Maximal number of companions is {max_companions}."
  static String get companionEventsEmpty => 'FeatureUser.companionEventsEmpty'
      .tr(); // "Companion's events will appear here."
  static String get deleteCompanion =>
      'FeatureUser.deleteCompanion'.tr(); // "Delete companion"
  static String get deleteCompanionConfirm => 'FeatureUser.deleteCompanionConfirm'
      .tr(); // "By deleting your companion you will also sign him/her out of all signed in sessions."
  static String get noGroup => 'FeatureUser.noGroup'.tr();
  static String get manageCompanions => 'FeatureUser.manageCompanions'.tr();
  static String get assignCompanion => 'FeatureUser.assignCompanion'.tr();
  static String get companionAssigned => 'FeatureUser.companionAssigned'.tr();
  static String get unassignCompanion => 'FeatureUser.unassignCompanion'.tr();
  static String get searchCompanion => 'FeatureUser.searchCompanion'.tr();
  static String get companionLimitReached =>
      'FeatureUser.companionLimitReached'.tr();
  static String get companionAlreadyAssigned =>
      'FeatureUser.companionAlreadyAssigned'.tr();
  static String get companionOwnsAnother =>
      'FeatureUser.companionOwnsAnother'.tr();
  static String get companionOwnerIsAssigned =>
      'FeatureUser.companionOwnerIsAssigned'.tr();
}
