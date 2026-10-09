import { LocalizationService } from '../../services/localization_service.js';

export class CommonStrings {
    static signupLegalNotice(terms, privacy) { return LocalizationService.tr("FeatureUser.signupLegalNotice", { button: CommonStrings.createAccount, terms, privacy }); }
    static get signupTerms() { return LocalizationService.tr("FeatureUser.signupTerms"); }
    static get signupPrivacy() { return LocalizationService.tr("FeatureUser.signupPrivacy"); }
    static get googlePasswordVisibility() { return LocalizationService.tr("FeatureUser.googlePasswordVisibility"); }
    static get googleUnlinkProof() { return LocalizationService.tr("FeatureUser.googleUnlinkProof"); }
    static get googleContinue() { return LocalizationService.tr("FeatureUser.googleContinue"); }
    static get googleSubtitle() { return LocalizationService.tr("FeatureUser.googleSubtitle"); }
    static get googleOr() { return LocalizationService.tr("FeatureUser.googleOr"); }
    static get googleClose() { return LocalizationService.tr("FeatureUser.googleClose"); }
    static get googleOpening() { return LocalizationService.tr("FeatureUser.googleOpening"); }
    static get googleCompleting() { return LocalizationService.tr("FeatureUser.googleCompleting"); }
    static get googleProof() { return LocalizationService.tr("FeatureUser.googleProof"); }
    static get googleLink() { return LocalizationService.tr("FeatureUser.googleLink"); }
    static get googleProfile() { return LocalizationService.tr("FeatureUser.googleProfile"); }
    static get googleConsent() { return LocalizationService.tr("FeatureUser.googleConsent"); }
    static get googleCreate() { return LocalizationService.tr("FeatureUser.googleCreate"); }
    static get googleRetry() { return LocalizationService.tr("FeatureUser.googleRetry"); }
    static get googleCancelled() { return LocalizationService.tr("FeatureUser.googleCancelled"); }
    static get googleExpired() { return LocalizationService.tr("FeatureUser.googleExpired"); }
    static get googleError() { return LocalizationService.tr("FeatureUser.googleError"); }
    static get googleProofError() { return LocalizationService.tr("FeatureUser.googleProofError"); }
    static get googleLeaveDraft() { return LocalizationService.tr("FeatureUser.googleLeaveDraft"); }
    static get googleMailbox() { return LocalizationService.tr("FeatureUser.googleMailbox"); }
    static get googleSendCode() { return LocalizationService.tr("FeatureUser.googleSendCode"); }
    static get googleVerifyCode() { return LocalizationService.tr("FeatureUser.googleVerifyCode"); }
    static get googleCode() { return LocalizationService.tr("FeatureUser.googleCode"); }
    static get googleUnlink() { return LocalizationService.tr("FeatureUser.googleUnlink"); }
    static get googleMfa() { return LocalizationService.tr("FeatureUser.googleMfa"); }

    static get googleTerms() { return LocalizationService.tr("FeatureUser.googleTerms"); }
    static get googlePrivacy() { return LocalizationService.tr("FeatureUser.googlePrivacy"); }
    static get emailExample() { return LocalizationService.tr("FeatureUser.emailExample"); }
    static get firstNameExample() { return LocalizationService.tr("FeatureUser.firstNameExample"); }
    static get lastNameExample() { return LocalizationService.tr("FeatureUser.lastNameExample"); }
    static get passwordPlaceholder() { return LocalizationService.tr("FeatureUser.passwordPlaceholder"); }
    static get emailAlternative() { return LocalizationService.tr("FeatureUser.emailAlternative"); }
    static get existingAccountPrompt() { return LocalizationService.tr("FeatureUser.existingAccountPrompt"); }
    static get newAccountPrompt() { return LocalizationService.tr("FeatureUser.newAccountPrompt"); }
    static get createAccount() { return LocalizationService.tr("FeatureUser.createAccount"); }
    static get signIn() { return LocalizationService.tr("FeatureUser.signIn"); }
    static get signOut() { return LocalizationService.tr("FeatureUser.signOut"); }
    static get addEvent() { return LocalizationService.tr("FeatureUser.addEvent", {}, "Create your own event"); }
    static get myEvents() { return LocalizationService.tr("FeatureUser.myEvents", {}, "My events"); }
    static get admin() { return LocalizationService.tr("FeatureUser.admin", {}, "Admin"); }
    static get email() { return LocalizationService.tr("FeatureUser.email"); }
    static get password() { return LocalizationService.tr("FeatureUser.password"); }
    static get login() { return LocalizationService.tr("FeatureUser.logIn"); }
    static get register() { return LocalizationService.tr("FeatureUser.register"); }
    static get signUp() { return LocalizationService.tr("FeatureUser.signUp"); }
    static get forgotPassword() { return LocalizationService.tr("FeatureUser.forgotPasswordQuestion"); }
    static get forgotYourPassword() { return LocalizationService.tr("FeatureUser.forgotYourPassword"); }
    static get sendResetEmail() { return LocalizationService.tr("FeatureUser.sendResetEmail"); }
    static get iAm() { return LocalizationService.tr("FeatureUser.iAm"); }
    static get language() { return LocalizationService.tr("Common.languageSettings"); }
    static get resetPassword() { return LocalizationService.tr("FeatureUser.resetPassword"); }
    static get enterEmail() { return LocalizationService.tr("FeatureUser.enterEmailReset"); }
    static get firstName() { return LocalizationService.tr("Common.name"); }
    static get lastName() { return LocalizationService.tr("PersonFields.surname"); }
    static get confirmPassword() { return LocalizationService.tr("FeatureUser.confirmPassword"); }
    static get back() { return LocalizationService.tr("Common.back"); }
    static get send() { return LocalizationService.tr("Common.send"); }
    static get emailRequired() { return LocalizationService.tr("FeatureUser.emailInvalid"); }
    static get passwordRequired() { return LocalizationService.tr("FeatureUser.fillPassword"); }
    static get passwordMismatch() { return LocalizationService.tr("FeatureUser.passwordsDoNotMatch"); }
    static get passwordLength() { return LocalizationService.tr("FeatureUser.passwordMinLength"); }
    static get invalidEmail() { return LocalizationService.tr("FeatureUser.emailInvalid"); }
    static get checkEmail() { return LocalizationService.tr("FeatureUser.credentialsSent"); }
    static get passwordResetSent() { return LocalizationService.tr("FeatureUser.passwordResetSent"); }
    static get loading() { return LocalizationService.tr("Common.loading"); }
    static get retry() { return LocalizationService.tr('Common.retry', {}, 'Try again'); }
    static get success() { return LocalizationService.tr("Common.success"); }
    static get error() { return LocalizationService.tr("Common.error"); }
    
    // New additions
    static get light() { return LocalizationService.tr("Common.light"); }
    static get dark() { return LocalizationService.tr("Common.dark"); }
    static get auto() { return LocalizationService.tr("Common.auto"); }
    static get newPassword() { return LocalizationService.tr("FeatureUser.newPassword"); }
    static get changePassword() { return LocalizationService.tr("FeatureUser.changePasswordTitle"); }
    static get passwordChanged() { return LocalizationService.tr("FeatureUser.passwordChanged"); }
    static get createAPassword() { return LocalizationService.tr("FeatureUser.createPasswordToContinue"); }
    static get tokenInvalid() { return LocalizationService.tr("FeatureUser.tokenInvalid"); }
    static get registrationFailed() { return LocalizationService.tr("FeatureUser.registrationFailed"); }
    static get emailInUse() { return LocalizationService.tr("FeatureUser.emailInUse"); }
    static get invalidCredentials() { return LocalizationService.tr("FeatureUser.invalidCredentials"); }
    static get fieldRequired() { return LocalizationService.tr("Common.fieldCannotBeEmpty"); }
    static get edit() { return LocalizationService.tr("Common.edit"); }
    static get delete() { return LocalizationService.tr("Common.delete"); }
    static get save() { return LocalizationService.tr("Common.save"); }
    static get reset() { return LocalizationService.tr("Common.reset"); }
    static get processing() { return LocalizationService.tr("Common.processing"); }
}
