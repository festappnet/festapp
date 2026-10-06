import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/database_tables/tb.dart';

/// Represents a substitution definition for an email template.
class EmailTemplateSub {
  final String code;
  final String description;
  final String defaultValue;

  const EmailTemplateSub({
    required this.code,
    required this.description,
    required this.defaultValue,
  });

  @override
  String toString() {
    return "$code: $description";
  }
}

class EmailTemplateModel {
  int? id;
  String? html;
  int? occasion;
  String? subject;
  int? organization;
  String? code;
  int? unit;
  String? title;

  EmailTemplateModel({
    this.id,
    this.html,
    this.occasion,
    this.subject,
    this.organization,
    this.code,
    this.unit,
    this.title,
  });

  factory EmailTemplateModel.fromJson(Map<String, dynamic> json) {
    return EmailTemplateModel(
      id: json[Tb.email_templates.id],
      html: json[Tb.email_templates.html],
      occasion: json[Tb.email_templates.occasion],
      subject: json[Tb.email_templates.subject],
      organization: json[Tb.email_templates.organization],
      code: json[Tb.email_templates.code],
      unit: json[Tb.email_templates.unit],
      title: json[Tb.email_templates.title],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.email_templates.id: id,
      Tb.email_templates.html: html,
      Tb.email_templates.occasion: occasion,
      Tb.email_templates.subject: subject,
      Tb.email_templates.organization: organization,
      Tb.email_templates.code: code,
      Tb.email_templates.unit: unit,
      Tb.email_templates.title: title,
    };
  }

  // Common substitution definitions (codes are now without '{{' and '}}'):
  static EmailTemplateSub appPlatformLinksSub = EmailTemplateSub(
    code: 'platformLinks',
    description: EmailTemplatesStrings.subPlatformLinks,
    defaultValue: 'Open the app on https://live.festapp.net/.',
  );

  static EmailTemplateSub appLinksSub = EmailTemplateSub(
    code: 'appLinks',
    description: EmailTemplatesStrings.subPlatformLinks,
    defaultValue: 'Open the app on https://live.festapp.net/.',
  );

  static EmailTemplateSub appNameSub = EmailTemplateSub(
    code: 'appName',
    description: EmailTemplatesStrings.subAppName,
    defaultValue: 'Festapp',
  );

  static EmailTemplateSub emailSub = EmailTemplateSub(
    code: 'email',
    description: EmailTemplatesStrings.subEmail,
    defaultValue: 'jan.novak@festapp.net',
  );

  static EmailTemplateSub nameSub = EmailTemplateSub(
    code: 'name',
    description: EmailTemplatesStrings.subName,
    defaultValue: 'Jan',
  );

  static EmailTemplateSub surnameSub = EmailTemplateSub(
    code: 'surname',
    description: EmailTemplatesStrings.subSurname,
    defaultValue: 'Novák',
  );

  static EmailTemplateSub resetLinkSub = EmailTemplateSub(
    code: 'resetLink',
    description: EmailTemplatesStrings.subResetLink,
    defaultValue: 'https://live.festapp.net/reset',
  );

  static EmailTemplateSub signInCodeSub = EmailTemplateSub(
    code: 'code',
    description: EmailTemplatesStrings.subSignInCode,
    defaultValue: '123456',
  );

  static EmailTemplateSub occasionTitleSub = EmailTemplateSub(
    code: 'occasionTitle',
    description: EmailTemplatesStrings.subOccasionTitle,
    defaultValue: 'Festival of Creaky Music',
  );

  static EmailTemplateSub amountSub = EmailTemplateSub(
    code: 'amount',
    description: EmailTemplatesStrings.subAmount,
    defaultValue: '100 CZK',
  );

  static EmailTemplateSub accountNumberSub = EmailTemplateSub(
    code: 'accountNumber',
    description: EmailTemplatesStrings.subAccountNumber,
    defaultValue: '2502719268/2010',
  );

  static EmailTemplateSub ibanSub = EmailTemplateSub(
    code: 'iban',
    description: EmailTemplatesStrings.subIban,
    defaultValue: 'CZ4520100000002502719268',
  );

  static EmailTemplateSub orderSymbolSub = EmailTemplateSub(
    code: 'orderSymbol',
    description: OrdersStrings.gridOrderSymbol,
    defaultValue: '7G4K9M2R6A',
  );

  static EmailTemplateSub variableSymbolSub = EmailTemplateSub(
    code: 'variableSymbol',
    description: EmailTemplatesStrings.subVariableSymbol,
    defaultValue: '9654',
  );

  static EmailTemplateSub deadlineSub = EmailTemplateSub(
    code: 'deadline',
    description: EmailTemplatesStrings.subDeadline,
    defaultValue: '30. 2. 2026',
  );

  static EmailTemplateSub fullOrderSub = EmailTemplateSub(
    code: 'fullOrder',
    description: EmailTemplatesStrings.subFullOrder,
    defaultValue: 'Order details here',
  );

  static EmailTemplateSub changeOverviewSub = EmailTemplateSub(
    code: 'changeOverview',
    description: EmailTemplatesStrings.subChangeOverview,
    defaultValue: 'Here is an overview of the changes in your order.',
  );

  static EmailTemplateSub balanceReasoningSub = EmailTemplateSub(
    code: 'balanceReasoning',
    description: EmailTemplatesStrings.subBalanceReasoning,
    defaultValue: 'Your order is fully paid.',
  );

  static EmailTemplateSub paymentDetailsSub = EmailTemplateSub(
    code: 'paymentDetails',
    description: EmailTemplatesStrings.subPaymentDetails,
    defaultValue: 'Payment details table',
  );

  static EmailTemplateSub remainingTimeSub = EmailTemplateSub(
    code: 'remainingTime',
    description: EmailTemplatesStrings.subRemainingTime,
    defaultValue: '5 days',
  );

  static EmailTemplateSub confirmationUrlSub = EmailTemplateSub(
    code: 'confirmationUrl',
    description: EmailTemplatesStrings.subConfirmationUrl,
    defaultValue: 'https://live.festapp.net/delete-account/confirm',
  );

  static EmailTemplateSub expiresAtSub = EmailTemplateSub(
    code: 'expiresAt',
    description: EmailTemplatesStrings.subExpiresAt,
    defaultValue: '31. 12. 2026 23:59',
  );

  /// Mapping of template codes to their available substitutions.
  static final Map<String, List<EmailTemplateSub>> substitutionDefinitions = {
    'RESET_PASSWORD': [
      appNameSub,
      appPlatformLinksSub,
      emailSub,
      resetLinkSub,
    ],
    'SIGN_IN_CODE': [
      appNameSub,
      appPlatformLinksSub,
      emailSub,
      nameSub,
      surnameSub,
      signInCodeSub,
    ],
    'APP_LINKS': [appLinksSub],
    'ACCOUNT_DELETION_CONFIRM': [
      appNameSub,
      confirmationUrlSub,
      expiresAtSub,
    ],
    'ACCOUNT_DELETION_COMPLETE': [appNameSub],
    'TICKET_ORDER_CONFIRMATION': [
      orderSymbolSub,
      occasionTitleSub,
      amountSub,
      accountNumberSub,
      ibanSub,
      variableSymbolSub,
      deadlineSub,
      balanceReasoningSub,
      fullOrderSub,
    ],
    'TICKET_ORDER_UPDATE': [
      orderSymbolSub,
      occasionTitleSub,
      fullOrderSub,
      changeOverviewSub,
      balanceReasoningSub,
    ],
    'TICKET_ORDER_PAYMENT_DONE': [
      orderSymbolSub,
      occasionTitleSub,
      fullOrderSub,
      balanceReasoningSub,
      amountSub,
    ],
    'TICKET_ORDER_REMINDER': [
      orderSymbolSub,
      occasionTitleSub,
      balanceReasoningSub,
      fullOrderSub,
      amountSub,
      deadlineSub,
      paymentDetailsSub,
      remainingTimeSub,
    ],
    'TICKET_ORDER_STORNO': [
      orderSymbolSub,
      occasionTitleSub,
      amountSub,
    ],
  };

  /// Returns usage details based on the template code.
  /// The returned map includes:
  /// - 'title': A translated title for the template.
  /// - 'description': A translated description of what the template is used for.
  /// - 'subs': A list of [EmailTemplateSub] objects for available substitutions.
  Map<String, dynamic> getUsageDetails() {
    switch (code) {
      case 'RESET_PASSWORD':
        return {
          'title': EmailTemplatesStrings.usageResetPasswordTitle,
          'description': EmailTemplatesStrings.usageResetPasswordDescription,
          'subs': substitutionDefinitions['RESET_PASSWORD'] ?? [],
        };
      case 'SIGN_IN_CODE':
        return {
          'title': EmailTemplatesStrings.usageSignInCodeTitle,
          'description': EmailTemplatesStrings.usageSignInCodeDescription,
          'subs': substitutionDefinitions['SIGN_IN_CODE'] ?? [],
        };
      case 'APP_LINKS':
        return {
          'title': EmailTemplatesStrings.usageAppLinksTitle,
          'description': EmailTemplatesStrings.usageAppLinksDescription,
          'subs': substitutionDefinitions['APP_LINKS'] ?? [],
        };
      case 'ACCOUNT_DELETION_CONFIRM':
        return {
          'title': EmailTemplatesStrings.usageAccountDeletionConfirmTitle,
          'description':
              EmailTemplatesStrings.usageAccountDeletionConfirmDescription,
          'subs': substitutionDefinitions['ACCOUNT_DELETION_CONFIRM'] ?? [],
        };
      case 'ACCOUNT_DELETION_COMPLETE':
        return {
          'title': EmailTemplatesStrings.usageAccountDeletionCompleteTitle,
          'description':
              EmailTemplatesStrings.usageAccountDeletionCompleteDescription,
          'subs': substitutionDefinitions['ACCOUNT_DELETION_COMPLETE'] ?? [],
        };
      case 'TICKET_ORDER_CONFIRMATION':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderConfirmationTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderConfirmationDescription,
          'subs': substitutionDefinitions['TICKET_ORDER_CONFIRMATION'] ?? [],
        };
      case 'TICKET_ORDER_UPDATE':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderUpdateTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderUpdateDescription,
          'subs': substitutionDefinitions['TICKET_ORDER_UPDATE'] ?? [],
        };
      case 'TICKET_ORDER_PAYMENT_DONE':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderPaymentDoneTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderPaymentDoneDescription,
          'subs': substitutionDefinitions['TICKET_ORDER_PAYMENT_DONE'] ?? [],
        };
      case 'TICKET_ORDER_REMINDER':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderPaymentReminderTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderPaymentReminderDescription,
          'subs': substitutionDefinitions['TICKET_ORDER_REMINDER'] ?? [],
        };
      case 'TICKET_ORDER_STORNO':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderStornoTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderStornoDescription,
          'subs': substitutionDefinitions['TICKET_ORDER_STORNO'] ?? [],
        };
      default:
        return {
          'title': title?.trim().isNotEmpty == true
              ? title!.trim()
              : (code?.trim().isNotEmpty == true ? code!.trim() : '-'),
          'description': '-',
          'subs': [],
        };
    }
  }
}
