import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/event_feedback/event_feedback_model.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class EventFeedbackCommands {
  Future<EventFeedbackModel> submit({
    required int occasionId,
    required int eventId,
    required String rating,
    required String? note,
    required String? anonymousClientId,
  });

  Future<void> delete({
    required int occasionId,
    required int eventId,
    required String? anonymousClientId,
  });

  Future<void> deleteForEdit({
    required int occasionId,
    required int feedbackId,
  });
}

class SupabaseEventFeedbackCommands implements EventFeedbackCommands {
  SupabaseEventFeedbackCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseEventFeedbackCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<EventFeedbackModel> submit({
    required int occasionId,
    required int eventId,
    required String rating,
    required String? note,
    required String? anonymousClientId,
  }) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'submit_event_feedback_client_sync_v1',
      {
        'p_occasion': occasionId,
        'p_event': eventId,
        'p_rating': rating,
        'p_note': note,
        'p_client_id': anonymousClientId,
      },
    ));
    if (response.status == 'rejected') {
      throw EventFeedbackException(
          response.code, response.data['message'] as String?);
    }
    final raw = response.data['feedback'];
    if (response.code != 200 || raw is! Map) {
      throw StateError('Feedback command omitted its authoritative result');
    }
    await applyClientCommandReplacements(response);
    return EventFeedbackModel.fromJson(raw.cast<String, dynamic>());
  }

  @override
  Future<void> delete({
    required int occasionId,
    required int eventId,
    required String? anonymousClientId,
  }) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_event_feedback_client_sync_v1',
      {
        'p_occasion': occasionId,
        'p_event': eventId,
        'p_client_id': anonymousClientId,
      },
    ));
    if (response.status == 'rejected') {
      throw EventFeedbackException(
          response.code, response.data['message'] as String?);
    }
    if (response.code != 200 ||
        (response.status != 'applied' && response.status != 'unchanged')) {
      throw StateError('Feedback delete command failed');
    }
    await applyClientCommandReplacements(response);
  }

  @override
  Future<void> deleteForEdit({
    required int occasionId,
    required int feedbackId,
  }) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_event_feedback_for_edit_client_sync_v1',
      {
        'p_occasion': occasionId,
        'p_feedback': feedbackId,
      },
    ));
    if (response.status == 'rejected') {
      throw EventFeedbackException(
          response.code, response.data['message'] as String?);
    }
    if (response.code != 200 ||
        (response.status != 'applied' && response.status != 'unchanged')) {
      throw StateError('Admin feedback delete command failed');
    }
    await applyClientCommandReplacements(response);
  }
}
