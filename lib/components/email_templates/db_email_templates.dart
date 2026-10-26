import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:festapp_core/email_templates.dart';
import 'package:html/parser.dart' as html_parser;

class DbEmailTemplates {
  static final _supabase = Supabase.instance.client;

  static Future<EmailAuthoringContext> getAuthoringContext(
      EmailTemplatesResponse scope, String templateCode) async {
    final occasionId = scope.occasion?.id;
    final response =
        await _supabase.functions.invoke('send-custom-email', body: {
      'action': 'authoringContext',
      'entityType': occasionId != null ? 'occasion' : 'unit',
      'entityId': occasionId ?? scope.unit.id,
      'templateCode': templateCode,
    });
    if (response.status != 200 || response.data is! Map) {
      throw StateError('Email authoring metadata unavailable');
    }
    return EmailAuthoringContext.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  static Future<EmailTemplatesResponse> getAllEmailTemplatesViaOccasionLink(
      String link) async {
    final response = await _supabase.rpc(
        "get_all_email_templates_via_occasion_link",
        params: {"occasion_link": link});
    final result = EmailTemplatesResponse.fromJson(response);
    // This RPC intentionally returns only occasion metadata; retain the known
    // scoped route link so examples can use its existing catalog reader.
    result.occasion?.link = link;
    return result;
  }

  static Future<void> updateEmailTemplate(EmailTemplateModel template) async {
    await _supabase.rpc('update_email_template', params: {"p_data": template});
  }

  static Future<EmailTemplatesResponse> getEntityEmailTemplates({
    int? unitId,
    int? occasionId,
  }) async {
    final response = await _supabase.rpc("get_entity_email_templates", params: {
      "p_entity_type": unitId != null ? "unit" : "occasion",
      "p_entity_id": unitId ?? occasionId
    });
    return EmailTemplatesResponse.fromJson(response);
  }

  static Future<void> updateEntityEmailBanner({
    int? occasionId,
    int? unitId,
    String? bannerUrl,
  }) async {
    if (occasionId != null) {
      await _supabase.rpc('update_entity_email_banner', params: {
        "p_entity_type": "occasion",
        "p_entity_id": occasionId,
        "p_banner_url": bannerUrl
      });
    } else if (unitId != null) {
      await _supabase.rpc('update_entity_email_banner', params: {
        "p_entity_type": "unit",
        "p_entity_id": unitId,
        "p_banner_url": bannerUrl
      });
    }
  }

  static Future<void> deleteEntityEmailTemplate({
    int? occasionId,
    int? unitId,
    required String code,
  }) async {
    if (occasionId != null) {
      await _supabase.rpc('delete_entity_email_template', params: {
        "p_entity_type": "occasion",
        "p_entity_id": occasionId,
        "p_code": code
      });
    } else if (unitId != null) {
      await _supabase.rpc('delete_entity_email_template', params: {
        "p_entity_type": "unit",
        "p_entity_id": unitId,
        "p_code": code
      });
    }
  }
}

class EmailAuthoringContext {
  final String senderAddress;
  final String? wrapperHtml;
  final List<EmailPreviewPaymentAccount> paymentAccounts;
  const EmailAuthoringContext({required this.senderAddress, this.wrapperHtml,
    this.paymentAccounts = const []});

  factory EmailAuthoringContext.fromJson(Map<String, dynamic> json) {
    final sender = json['senderAddress'];
    if (sender is! String || sender.trim().isEmpty) {
      throw const FormatException('Missing canonical sender');
    }
    return EmailAuthoringContext(
        senderAddress: sender, wrapperHtml: json['wrapperHtml'] as String?,
        paymentAccounts: [
          for (final value in (json['paymentAccounts'] as List? ?? const []))
            if (value is Map && value['accountNumber'] is String && value['iban'] is String && value['currencies'] is List)
              EmailPreviewPaymentAccount(accountNumber: value['accountNumber'],
                iban: value['iban'], currencies: List<String>.from(value['currencies'])),
        ]);
  }

  String composeHtml(EmailPreviewScenario scenario, String body) =>
      scenario.composeHtml(body, wrapperHtml: wrapperHtml);

  /// Only images from the resolved wrapper can opt into remote preview.
  /// Other email images, including tracking pixels, remain inert.
  Set<String> get bannerImageSources => {
        for (final image
            in html_parser.parse(wrapperHtml ?? '').querySelectorAll('img'))
          if (_isCanonicalBanner(image.attributes['src'] ?? ''))
            image.attributes['src']!,
      };

  static bool _isCanonicalBanner(String source) {
    final uri = Uri.tryParse(source);
    return uri != null &&
        uri.scheme == 'https' &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        const {'img.festapp.net', 'a.img.festapp.net'}.contains(uri.host) &&
        (uri.path.startsWith('/images/') || uri.path.startsWith('/assets/')) &&
        !source.split(RegExp(r'[?#]')).first.contains('%') &&
        !uri.pathSegments.contains('..');
  }
}

class EmailTemplatesResponse {
  final OccasionModel? occasion;
  final UnitModel unit;
  final UnitModel organization;
  final List<EmailTemplateModel> templates;

  EmailTemplatesResponse({
    this.occasion,
    required this.unit,
    required this.organization,
    required this.templates,
  });

  factory EmailTemplatesResponse.fromJson(Map<String, dynamic> json) {
    return EmailTemplatesResponse(
      occasion: json['occasion'] != null
          ? OccasionModel.fromJson(json['occasion'])
          : null,
      unit: UnitModel.fromJson(json['unit']),
      organization: UnitModel.fromJson(json['organization']),
      templates: (json['templates'] as List)
          .map((x) => EmailTemplateModel.fromJson(x))
          .toList(),
    );
  }
}
