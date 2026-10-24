import 'package:fstapp/components/event_feedback/event_feedback_model.dart';
import 'package:fstapp/components/event_feedback/event_feedback_commands.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Data access for the EventFeedback feature. Backed by the SECURITY DEFINER
/// RPCs submit/get/delete_event_feedback (+ admin for_edit / export_for_edit).
class DbEventFeedback {
  static final _supabase = Supabase.instance.client;
  static EventFeedbackCommands get _commands =>
      SupabaseEventFeedbackCommands(_supabase);
  static Future<String> _clientId() => ClientCommandIdentity.clientId();

  /// Current viewer's feedback for [eventId], or null.
  static Future<EventFeedbackModel?> getMyFeedback(int eventId) async {
    if (ClientSyncRuntime.isV1Selected && AuthService.isLoggedIn()) {
      return ClientSyncProjection.feedback(eventId);
    }
    final params = <String, dynamic>{'p_event': eventId};
    if (!AuthService.isLoggedIn()) {
      params['p_client_id'] = await _clientId();
    }
    final res = await _supabase.rpc('get_event_feedback', params: params);
    _ensureOk(res);
    final data = res['data'];
    if (data == null) return null;
    return EventFeedbackModel.fromJson((data as Map).cast<String, dynamic>());
  }

  static Future<EventFeedbackModel> submit({
    required int eventId,
    required String rating,
    String? note,
  }) async {
    return _commands.submit(
      occasionId: RightsService.currentOccasionId()!,
      eventId: eventId,
      rating: rating,
      note: note,
      anonymousClientId: AuthService.isLoggedIn() ? null : await _clientId(),
    );
  }

  static Future<void> delete(int eventId) async {
    await _commands.delete(
      occasionId: RightsService.currentOccasionId()!,
      eventId: eventId,
      anonymousClientId: AuthService.isLoggedIn() ? null : await _clientId(),
    );
    return;
  }

  static Future<EventFeedbackForEdit> getForEdit(int eventId) async {
    final res = await _supabase
        .rpc('get_event_feedback_for_edit', params: {'p_event': eventId});
    _ensureOk(res);
    return EventFeedbackForEdit.fromJson(
        (res['data'] as Map).cast<String, dynamic>());
  }

  /// Flat per-event-per-respondent rows for CSV export of a whole occasion.
  static Future<List<Map<String, dynamic>>> exportForEdit(
      int occasionId) async {
    final res = await _supabase.rpc('get_event_feedback_export_for_edit',
        params: {'p_occasion': occasionId});
    _ensureOk(res);
    return ((res['data'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<void> deleteForEdit(int occasionId, int feedbackId) =>
      _commands.deleteForEdit(
        occasionId: occasionId,
        feedbackId: feedbackId,
      );

  static void _ensureOk(dynamic res) {
    if (res is Map && res['code'] != null && res['code'] != 200) {
      throw EventFeedbackException(
          (res['code'] as num).toInt(), res['message'] as String?);
    }
  }
}
