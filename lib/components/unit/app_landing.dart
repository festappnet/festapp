import 'package:supabase_flutter/supabase_flutter.dart';

class AppLanding {
  final bool enabled;
  final bool canManage;
  final int? occasionId;
  final String? occasionTitle;

  const AppLanding(
      {required this.enabled,
      required this.canManage,
      this.occasionId,
      this.occasionTitle});

  factory AppLanding.fromJson(Map<String, dynamic> json) => AppLanding(
        enabled: json['enabled'] == true,
        canManage: json['can_manage'] == true,
        occasionId: (json['occasion_id'] as num?)?.toInt(),
        occasionTitle: json['occasion_title'] as String?,
      );

  static Future<AppLanding> load(int unitId) async =>
      AppLanding.fromJson(await Supabase.instance.client
          .rpc('get_unit_app_landing', params: {'p_unit': unitId}));

  Future<AppLanding> save(int unitId, int? newOccasionId) async =>
      AppLanding.fromJson(
          await Supabase.instance.client.rpc('set_unit_app_landing', params: {
        'p_unit': unitId,
        'p_occasion': newOccasionId,
        'p_expected_occasion': occasionId,
      }));
}
