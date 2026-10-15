import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:festapp_core/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AttendanceAction { signIn, signOut }

class AttendanceCommandResult {
  const AttendanceCommandResult({
    required this.code,
    required this.isSignedIn,
    this.eventsRegistrationStart,
  });

  final int code;
  final bool isSignedIn;
  final String? eventsRegistrationStart;
}

abstract interface class AttendanceCommands {
  Future<AttendanceCommandResult> setAttendance({
    required int eventId,
    required String participantId,
    required AttendanceAction action,
  });
}

class SupabaseAttendanceCommands implements AttendanceCommands {
  SupabaseAttendanceCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  final ClientCommandTransport _transport;

  @override
  Future<AttendanceCommandResult> setAttendance({
    required int eventId,
    required String participantId,
    required AttendanceAction action,
  }) async {
    final raw = await _transport.invoke('set_event_attendance_client_sync_v1', {
      'p_event_id': eventId,
      'p_participant_id': participantId,
      'p_action': action == AttendanceAction.signIn ? 'sign_in' : 'sign_out',
    });
    final response = ClientCommandResponse.from(raw);
    await applyClientCommandReplacements(response);
    final data = response.data;
    return AttendanceCommandResult(
      code: response.code,
      isSignedIn: data['isSignedIn'] == true,
      eventsRegistrationStart: data['eventsRegistrationStart'] as String?,
    );
  }
}
