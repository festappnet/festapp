import 'dart:convert';
import 'email_template_model.dart';
import 'email_preview_context_loader.dart';
import '../occasion/occasion_model.dart';
import 'package:flutter/services.dart';
import 'package:festapp_core/email_templates.dart';
export 'package:festapp_core/email_templates.dart'
    show EmailPreviewScenario, EmailRequiredLink;

/// Deterministic build-time snapshots of the production email renderers.
class EmailPreviewExamples {
  final List<EmailPreviewScenario> records;
  final EmailPreviewContext? context;
  final bool contextUnavailable;
  bool get usesOccasionProducts => context?.products.isNotEmpty == true;
  bool get hasOccasionContext => context?.occasionTitle?.isNotEmpty == true;
  EmailPreviewExamples.fromJson(Map<String, dynamic> json,
      {this.context, this.contextUnavailable = false})
      : records = (json['records'] as List)
            .map((v) => EmailPreviewScenario.fromJson(
                Map<String, dynamic>.from(v as Map)))
            .toList(growable: false) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported email preview asset');
    }
  }
  static Future<EmailPreviewExamples> load() async =>
      EmailPreviewExamples.fromJson(jsonDecode(await rootBundle
              .loadString('assets/email_templates/preview_examples.json'))
          as Map<String, dynamic>);
  static Future<EmailPreviewExamples> loadForOccasion(
      OccasionModel? occasion) async {
    final data = jsonDecode(await rootBundle
            .loadString('assets/email_templates/preview_examples.json'))
        as Map<String, dynamic>;
    final result = await loadEmailPreviewContext(occasion);
    return EmailPreviewExamples.fromJson(data,
        context: result.context, contextUnavailable: result.unavailable);
  }

  List<EmailPreviewScenario> scenariosFor(String templateCode,
      {List<EmailPreviewPaymentAccount> paymentAccounts = const []}) {
    final codes = (EmailTemplateModel.substitutionDefinitions[templateCode] ??
            const <EmailTemplateSub>[])
        .map((entry) => entry.code)
        .toSet();
    return records.where((r) => r.templateCode == templateCode).map((r) {
      final currency = context?.products.firstOrNull?.currency ??
          r.contextDefaults['preview_currency'] ??
          'CZK';
      final account = paymentAccounts
          .where((a) => a.currencies.contains(currency))
          .firstOrNull;
      final effective =
          (context ?? const EmailPreviewContext()).withPaymentAccount(account);
      return (context == null && account == null ? r : r.withContext(effective))
          .restrictTo(codes);
    }).toList(growable: false);
  }
}
