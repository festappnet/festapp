import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:festapp_core/email_templates.dart';
import '../html/template_authoring.dart';
import 'email_template_model.dart';
import 'email_templates_strings.dart';
import 'email_preview_html.dart';

class EmailAuthoringProvider extends TemplateAuthoringProvider {
  EmailAuthoringProvider(this.template, {required this.field, this.scenario});
  final EmailTemplateModel template;
  late final List<EmailTemplateSub> _subs = template.substitutions;
  final EmailTargetField field;
  EmailPreviewScenario? scenario;
  WidgetBuilder? footerBuilder;
  VoidCallback? onSelectionChanged;
  @override
  void selectionChanged() => onSelectionChanged?.call();
  @override
  Widget? footer(BuildContext context) => footerBuilder?.call(context);
  @override
  bool get singleLine => field == EmailTargetField.subject;
  @override
  TextStyle get textStyle => emailContentTextStyle;
  @override
  Set<String> get codes => _subs.map((s) => s.code).toSet();
  String _label(EmailTemplateSub sub) {
    if (const {
      'fullOrder',
      'balanceReasoning',
      'paymentDetails',
      'changeOverview',
      'platformLinks',
      'appLinks'
    }.contains(sub.code))
      return 'EmailTemplates.authoring.labels.${sub.code}'.tr();
    if (sub.code == 'order_symbol' || sub.code == 'orderSymbol')
      return 'EmailTemplates.authoring.labels.orderSymbol'.tr();
    const aliases = {
      'occasion_title': 'occasionTitle',
      'participant_count': 'participantCount',
      'manage_waitlist_url': 'manageWaitlistUrl',
      'manage_waitlist_button': 'manageWaitlistButton',
      'offered_count': 'offeredCount',
      'offer_expires_at': 'offerExpiresAt',
      'offer_url': 'offerUrl',
      'offer_button': 'offerButton',
      'participant_phrase': 'participantCount',
      'offered_places': 'offeredCount',
      'order_overview_url': 'orderOverviewUrl',
      'order_overview_button': 'orderOverviewButton'
    };
    final key = 'EmailTemplates.subs.${aliases[sub.code] ?? sub.code}';
    final value = key.tr();
    return value == key ? sub.description : value;
  }

  @override
  TemplateAuthoringEntry? entry(String code) {
    final sub = _subs.where((s) => s.code == code).firstOrNull;
    if (sub == null) return null;
    final rich = sub.kind == EmailValueKind.richInline ||
        sub.kind == EmailValueKind.richBlock;
    return TemplateAuthoringEntry(
        code: code,
        label: _label(sub),
        description: sub.description,
        rich: rich,
        repeatable: sub.definition.repeatable,
        example:
            rich ? sub.description : scenario?.values[code] ?? sub.defaultValue,
        block: !singleLine && sub.kind == EmailValueKind.richBlock,
        url: sub.kind == EmailValueKind.url);
  }

  @override
  List<TemplateAuthoringEntry> search(String query, Map<String, int> usage) =>
      EmailTemplateRules.rank(_subs,
              definition: (s) => s.definition,
              label: _label,
              query: query,
              usage: usage,
              field: field)
          .map((s) => entry(s.code)!)
          .toList();
  @override
  bool canTrigger(String text, int offset,
          {bool inLink = false, bool inCode = false, bool composing = false}) =>
      EmailTemplateRules.canTrigger(text, offset,
          inLink: inLink, inCode: inCode, composing: composing);
  @override
  bool canInsert(String text, int offset,
          {bool inLink = false, bool inCode = false, bool composing = false}) =>
      EmailTemplateRules.canInsert(text, offset,
          inLink: inLink, inCode: inCode, composing: composing);
  @override
  String get helper => EmailTemplatesStrings.authoringHint;
  @override
  String get insertLabel => EmailTemplatesStrings.insertVariable;
  @override
  String get emptyLabel => EmailTemplatesStrings.noVariable;
  @override
  String get usedLabel => EmailTemplatesStrings.alreadyUsed;
  @override
  String get sampleLabel => EmailTemplatesStrings.sampleData;
  @override
  String get recommendedLabel => EmailTemplatesStrings.recommended;
  @override
  String get usedBlocksLabel => EmailTemplatesStrings.usedBlocks;
  @override
  String get uniqueUsedLabel => EmailTemplatesStrings.uniqueAlreadyUsed;
  @override
  String get unsupportedLabel => EmailTemplatesStrings.unknownVariable;
  @override
  String get tokenLabel => EmailTemplatesStrings.variable;
  @override
  Widget? preview(BuildContext context, String code) {
    final value = scenario?.values[code];
    return value == null
        ? Text(EmailTemplatesStrings.previewUnavailable)
        : EmailPreviewHtml(html: value);
  }
}
