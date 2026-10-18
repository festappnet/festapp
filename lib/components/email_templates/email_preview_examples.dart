import 'dart:convert';
import 'email_template_model.dart';
import 'package:flutter/services.dart';
import 'package:festapp_core/email_templates.dart';
export 'package:festapp_core/email_templates.dart'
    show EmailPreviewScenario, EmailRequiredLink;

/// Deterministic build-time snapshots of the production email renderers.
class EmailPreviewExamples {
  final List<EmailPreviewScenario> records;
  EmailPreviewExamples.fromJson(Map<String, dynamic> json)
      : records = (json['records'] as List)
            .map((v) => EmailPreviewScenario.fromJson(
                Map<String, dynamic>.from(v as Map)))
            .toList(growable: false) {
    if (json['version'] != 1)
      throw const FormatException('Unsupported email preview asset');
  }
  static Future<EmailPreviewExamples> load() async =>
      EmailPreviewExamples.fromJson(jsonDecode(await rootBundle
              .loadString('assets/email_templates/preview_examples.json'))
          as Map<String, dynamic>);
  List<EmailPreviewScenario> scenariosFor(String templateCode) {
    final codes = (EmailTemplateModel.substitutionDefinitions[templateCode] ??
            const <EmailTemplateSub>[])
        .map((entry) => entry.code)
        .toSet();
    return records
        .where((r) => r.templateCode == templateCode)
        .map((r) => r.restrictTo(codes))
        .toList(growable: false);
  }
}
