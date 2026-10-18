import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbEmailTemplates {
  static final _supabase = Supabase.instance.client;

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
