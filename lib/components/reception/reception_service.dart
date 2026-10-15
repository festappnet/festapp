import 'package:festapp_core/forms.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ReceptionService {
  static final _client = Supabase.instance.client;
  static const _uuid = Uuid();

  static String newCommandId() => _uuid.v4();

  static Future<Map<String, dynamic>> options() async =>
      _rpc('get_reception_registration_options_v1', {
        'p_occasion': RightsService.currentOccasionId(),
      });

  static Future<Map<String, dynamic>> create({
    required String commandId,
    required Map<String, dynamic> profile,
    int? groupId,
    String? accommodationCode,
    bool confirmSameName = false,
  }) async =>
      _rpc(
          'create_reception_user_v1',
          {
            'p_occasion': RightsService.currentOccasionId(),
            'p_command_id': commandId,
            'p_profile': profile,
            'p_group_id': groupId,
            'p_accommodation_code': accommodationCode,
            'p_confirm_same_name': confirmSameName,
          },
          allowConflict: true);

  static Future<Map<String, dynamic>> issue(String userId) async =>
      _rpc('issue_reception_login_qr_v1', {
        'p_occasion': RightsService.currentOccasionId(),
        'p_user': userId,
      });

  static Future<List<Map<String, dynamic>>> occasionUsers(String query) async {
    final value = await _client.rpc('get_reception_occasion_users_v1', params: {
      'p_occasion': RightsService.currentOccasionId(),
      'p_query': query,
    });
    return (value as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> recent() async {
    final value = await _client.rpc('get_my_recent_reception_registrations_v1',
        params: {'p_occasion': RightsService.currentOccasionId()});
    return (value as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Map<String, dynamic>> cancel(String userId) async {
    final response =
        await _client.functions.invoke('cancel-reception-registration', body: {
      'occasion': RightsService.currentOccasionId(),
      'user': userId,
      'commandId': newCommandId(),
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> _rpc(
      String name, Map<String, dynamic> params,
      {bool allowConflict = false}) async {
    final raw = await _client.rpc(name, params: params);
    final result = Map<String, dynamic>.from(raw as Map);
    if ((result['code'] as num?)?.toInt() == 200 ||
        (allowConflict &&
            result['message'] == 'same_name_confirmation_required'))
      return result;
    throw ReceptionCommandException(result);
  }
}
