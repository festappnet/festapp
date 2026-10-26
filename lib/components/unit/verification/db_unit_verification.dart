import 'package:supabase_flutter/supabase_flutter.dart';
import 'unit_legal_profile.dart';

typedef VerificationRpc = Future<dynamic> Function(
    String name, Map<String, dynamic> params);

class DbUnitVerification {
  final VerificationRpc _rpc;
  DbUnitVerification({VerificationRpc? rpc})
      : _rpc = rpc ??
            ((name, params) =>
                Supabase.instance.client.rpc(name, params: params));
  Future<Map<String, dynamic>> _call(
          String name, Map<String, dynamic> params) async =>
      Map<String, dynamic>.from(
          await _rpc(name, params).timeout(const Duration(seconds: 20)));
  Future<UnitLegalProfile> get(int unit) async =>
      UnitLegalProfile.fromJson(Map<String, dynamic>.from((await _call(
          'get_unit_legal_profile', {'p_unit': unit}))['profile']));
  Future<VerificationResult> save(
          UnitLegalProfile profile, Map<String, dynamic> draft) async =>
      VerificationResult.fromJson(await _call('save_unit_legal_profile', {
        'p_unit': profile.unitId,
        'p_expected_revision': profile.revision,
        'p_profile': {
          for (final key in UnitLegalProfile.fields) key: draft[key]
        }
      }));
  Future<VerificationResult> submit(UnitLegalProfile profile) async =>
      VerificationResult.fromJson(await _call('submit_unit_verification',
          {'p_unit': profile.unitId, 'p_expected_revision': profile.revision}));
  Future<VerificationResult> review(UnitLegalProfile profile, String decision,
          {String? feedback, String? note, String? source}) async =>
      VerificationResult.fromJson(await _call('review_unit_verification', {
        'p_unit': profile.unitId,
        'p_expected_revision': profile.revision,
        'p_decision': decision,
        'p_feedback': feedback,
        'p_note': note,
        'p_source': source
      }));
  Future<Map<String, dynamic>> queue(int organization, String status,
          {Map<String, dynamic>? cursor}) =>
      _call('get_unit_verification_queue', {
        'p_organization': organization,
        'p_status': status,
        'p_cursor': cursor,
        'p_limit': 50
      });
}
