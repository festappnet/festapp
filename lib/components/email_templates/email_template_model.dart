import 'package:festapp_core/email_templates.dart';
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

  EmailVariableDefinition get definition => EmailTemplateRules.definition(code);
  EmailValueKind get kind => definition.kind;
  bool supportsField(EmailTargetField field) => definition.supports(field);

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
  static EmailTemplateSub get appPlatformLinksSub => EmailTemplateSub(
        code: 'platformLinks',
        description: EmailTemplatesStrings.subPlatformLinks,
        defaultValue: '',
      );

  static EmailTemplateSub get appLinksSub => EmailTemplateSub(
        code: 'appLinks',
        description: EmailTemplatesStrings.subPlatformLinks,
        defaultValue: '',
      );

  static EmailTemplateSub get appNameSub => EmailTemplateSub(
        code: 'appName',
        description: EmailTemplatesStrings.subAppName,
        defaultValue: 'Festapp',
      );

  static EmailTemplateSub get emailSub => EmailTemplateSub(
        code: 'email',
        description: EmailTemplatesStrings.subEmail,
        defaultValue: 'jana.novakova@example.com',
      );

  static EmailTemplateSub get nameSub => EmailTemplateSub(
        code: 'name',
        description: EmailTemplatesStrings.subName,
        defaultValue: 'Jan',
      );

  static EmailTemplateSub get surnameSub => EmailTemplateSub(
        code: 'surname',
        description: EmailTemplatesStrings.subSurname,
        defaultValue: 'Novák',
      );

  static EmailTemplateSub get resetLinkSub => EmailTemplateSub(
        code: 'resetLink',
        description: EmailTemplatesStrings.subResetLink,
        defaultValue: 'https://example.invalid/reset',
      );

  static EmailTemplateSub get signInCodeSub => EmailTemplateSub(
        code: 'code',
        description: EmailTemplatesStrings.subSignInCode,
        defaultValue: '123456',
      );

  static EmailTemplateSub get occasionTitleSub => EmailTemplateSub(
        code: 'occasionTitle',
        description: EmailTemplatesStrings.subOccasionTitle,
        defaultValue: 'Festival of Creaky Music',
      );

  static EmailTemplateSub get amountSub => EmailTemplateSub(
        code: 'amount',
        description: EmailTemplatesStrings.subAmount,
        defaultValue: '100 CZK',
      );

  static EmailTemplateSub get accountNumberSub => EmailTemplateSub(
        code: 'accountNumber',
        description: EmailTemplatesStrings.subAccountNumber,
        defaultValue: '0000000000/0000',
      );

  static EmailTemplateSub get ibanSub => EmailTemplateSub(
        code: 'iban',
        description: EmailTemplatesStrings.subIban,
        defaultValue: '',
      );

  static EmailTemplateSub get orderSymbolSub => EmailTemplateSub(
        code: 'orderSymbol',
        description: OrdersStrings.gridOrderSymbol,
        defaultValue: '7G4K9M2R6A',
      );

  static EmailTemplateSub get variableSymbolSub => EmailTemplateSub(
        code: 'variableSymbol',
        description: EmailTemplatesStrings.subVariableSymbol,
        defaultValue: '9654',
      );

  static EmailTemplateSub get deadlineSub => EmailTemplateSub(
        code: 'deadline',
        description: EmailTemplatesStrings.subDeadline,
        defaultValue: '30. 10. 2026',
      );

  static EmailTemplateSub get fullOrderSub => EmailTemplateSub(
        code: 'fullOrder',
        description: EmailTemplatesStrings.subFullOrder,
        defaultValue: '',
      );

  static EmailTemplateSub get changeOverviewSub => EmailTemplateSub(
        code: 'changeOverview',
        description: EmailTemplatesStrings.subChangeOverview,
        defaultValue: '',
      );

  static EmailTemplateSub get balanceReasoningSub => EmailTemplateSub(
        code: 'balanceReasoning',
        description: EmailTemplatesStrings.subBalanceReasoning,
        defaultValue: '',
      );

  static EmailTemplateSub get paymentDetailsSub => EmailTemplateSub(
        code: 'paymentDetails',
        description: EmailTemplatesStrings.subPaymentDetails,
        defaultValue: '',
      );

  static EmailTemplateSub get remainingTimeSub => EmailTemplateSub(
        code: 'remainingTime',
        description: EmailTemplatesStrings.subRemainingTime,
        defaultValue: '5 days',
      );

  static EmailTemplateSub get confirmationUrlSub => EmailTemplateSub(
        code: 'confirmationUrl',
        description: EmailTemplatesStrings.subConfirmationUrl,
        defaultValue: 'https://example.invalid/delete-account/confirm',
      );

  static EmailTemplateSub get expiresAtSub => EmailTemplateSub(
        code: 'expiresAt',
        description: EmailTemplatesStrings.subExpiresAt,
        defaultValue: '31. 12. 2026 23:59',
      );

  /// Mapping of template codes to their available substitutions.
  static List<EmailTemplateSub> get orderOverviewSubs => [
        EmailTemplateSub(
            code: 'order_overview_url',
            description: EmailTemplatesStrings.subOrderOverviewUrlDescription,
            defaultValue:
                'https://example.invalid/order?order_id=1&token=preview'),
        EmailTemplateSub(
            code: 'order_overview_button',
            description:
                EmailTemplatesStrings.subOrderOverviewButtonDescription,
            defaultValue: ''),
      ];

  static List<EmailTemplateSub> get waitlistSubs => [
        ...orderOverviewSubs,
        EmailTemplateSub(
            code: 'order_symbol',
            description: OrdersStrings.gridOrderSymbol,
            defaultValue: '7G4K9M2R6A'),
        EmailTemplateSub(
            code: 'occasion_title',
            description: EmailTemplatesStrings.subOccasionTitle,
            defaultValue: 'Festival'),
        EmailTemplateSub(
            code: 'participant_count',
            description: EmailTemplatesStrings.subParticipantCount,
            defaultValue: '1'),
        EmailTemplateSub(
            code: 'participant_phrase',
            description: EmailTemplatesStrings.subParticipantCount,
            defaultValue: '1 osobu'),
        EmailTemplateSub(
            code: 'manage_waitlist_url',
            description: EmailTemplatesStrings.subManageWaitlistUrl,
            defaultValue:
                'https://example.invalid/order?waitlist=1&order_id=1&token=preview'),
        EmailTemplateSub(
            code: 'manage_waitlist_button',
            description: EmailTemplatesStrings.subManageWaitlistButton,
            defaultValue: ''),
      ];

  static Map<String, List<EmailTemplateSub>> get substitutionDefinitions => {
        'waitlist_confirmation': waitlistSubs,
        'waitlist_offer': [
          ...waitlistSubs,
          EmailTemplateSub(
              code: 'offered_count',
              description: EmailTemplatesStrings.subOfferedCount,
              defaultValue: '1'),
          EmailTemplateSub(
              code: 'offered_places',
              description: EmailTemplatesStrings.subOfferedCount,
              defaultValue: '1 místo'),
          EmailTemplateSub(
              code: 'offer_expires_at',
              description: EmailTemplatesStrings.subOfferExpiresAt,
              defaultValue: '14. 10. 2026 14:00'),
          EmailTemplateSub(
              code: 'offer_url',
              description: EmailTemplatesStrings.subOfferUrl,
              defaultValue:
                  'https://example.invalid/order?waitlist=1&offer_id=preview&token=preview'),
          EmailTemplateSub(
              code: 'offer_button',
              description: EmailTemplatesStrings.subOfferButton,
              defaultValue: ''),
        ],
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
          ...orderOverviewSubs,
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
          ...orderOverviewSubs,
          orderSymbolSub,
          occasionTitleSub,
          fullOrderSub,
          changeOverviewSub,
          balanceReasoningSub,
        ],
        'TICKET_ORDER_PAYMENT_DONE': [
          ...orderOverviewSubs,
          orderSymbolSub,
          occasionTitleSub,
          fullOrderSub,
          balanceReasoningSub,
          amountSub,
        ],
        'TICKET_ORDER_REMINDER': [
          ...orderOverviewSubs,
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
          ...orderOverviewSubs,
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
  List<EmailTemplateSub> get substitutions =>
      substitutionDefinitions[code] ?? const [];

  Map<String, dynamic> getUsageDetails() => {
        ..._usageDescription(),
        'subs': substitutions,
      };

  Map<String, dynamic> _usageDescription() {
    switch (code) {
      case 'waitlist_confirmation':
        return {
          'title': EmailTemplatesStrings.usageWaitlistConfirmationTitle,
          'description':
              EmailTemplatesStrings.usageWaitlistConfirmationDescription,
        };
      case 'waitlist_offer':
        return {
          'title': EmailTemplatesStrings.usageWaitlistOfferTitle,
          'description': EmailTemplatesStrings.usageWaitlistOfferDescription,
        };
      case 'RESET_PASSWORD':
        return {
          'title': EmailTemplatesStrings.usageResetPasswordTitle,
          'description': EmailTemplatesStrings.usageResetPasswordDescription,
        };
      case 'SIGN_IN_CODE':
        return {
          'title': EmailTemplatesStrings.usageSignInCodeTitle,
          'description': EmailTemplatesStrings.usageSignInCodeDescription,
        };
      case 'APP_LINKS':
        return {
          'title': EmailTemplatesStrings.usageAppLinksTitle,
          'description': EmailTemplatesStrings.usageAppLinksDescription,
        };
      case 'ACCOUNT_DELETION_CONFIRM':
        return {
          'title': EmailTemplatesStrings.usageAccountDeletionConfirmTitle,
          'description':
              EmailTemplatesStrings.usageAccountDeletionConfirmDescription,
        };
      case 'ACCOUNT_DELETION_COMPLETE':
        return {
          'title': EmailTemplatesStrings.usageAccountDeletionCompleteTitle,
          'description':
              EmailTemplatesStrings.usageAccountDeletionCompleteDescription,
        };
      case 'TICKET_ORDER_CONFIRMATION':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderConfirmationTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderConfirmationDescription,
        };
      case 'TICKET_ORDER_UPDATE':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderUpdateTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderUpdateDescription,
        };
      case 'TICKET_ORDER_PAYMENT_DONE':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderPaymentDoneTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderPaymentDoneDescription,
        };
      case 'TICKET_ORDER_REMINDER':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderPaymentReminderTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderPaymentReminderDescription,
        };
      case 'TICKET_ORDER_STORNO':
        return {
          'title': EmailTemplatesStrings.usageTicketOrderStornoTitle,
          'description':
              EmailTemplatesStrings.usageTicketOrderStornoDescription,
        };
      default:
        return {
          'title': title?.trim().isNotEmpty == true
              ? title!.trim()
              : (code?.trim().isNotEmpty == true ? code!.trim() : '-'),
          'description': '-',
        };
    }
  }
}
