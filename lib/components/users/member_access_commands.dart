import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:festapp_core/sync.dart';

class MemberAccessFailure implements Exception {
  const MemberAccessFailure(this.reasonCode);
  final String reasonCode;
}

class MemberAccessCommands {
  MemberAccessCommands(this.client)
    : transport = ClientCommandTransport((_, args) async {
        try {
          final response = await client.functions.invoke(
            'manage-member-access',
            body: {
              'commandId': args['p_command_id'],
              'request': args['p_request'],
            },
          );
          return response.data;
        } on FunctionException catch (error) {
          final details = error.details;
          throw MemberAccessFailure(
            details is Map
                ? details['reasonCode'] as String? ?? 'access_operation_failed'
                : 'access_operation_failed',
          );
        }
      });
  final SupabaseClient client;
  final ClientCommandTransport transport;

  Future<Map<String, dynamic>> send(Map<String, dynamic> request) async {
    final actor = client.auth.currentUser?.id;
    final token = ClientSyncRuntime.mutationContextToken;
    final result = ClientCommandResponse.from(
      await transport.invokeIntent(
        '$actor:access:${request['scope']}:${request['email'] ?? request['userId']}',
        'manage_member_access',
        {'p_request': request},
      ),
    );
    if (actor != client.auth.currentUser?.id ||
        !ClientSyncRuntime.isCurrentMutationContext(token)) {
      throw StateError('Reload access after context change');
    }
    if (result.code != 200) {
      if (result.code == 403)
        await RightsService.refreshAfterAuthorizationDenial();
      throw MemberAccessFailure(
        result.data['reasonCode'] as String? ?? 'access_operation_failed',
      );
    }
    return result.data;
  }

  Future<Map<String, dynamic>> status(String scope, int id) async {
    final actor = client.auth.currentUser?.id;
    final token = ClientSyncRuntime.mutationContextToken;
    final value = await client.rpc(
      'get_member_access_status',
      params: {'p_scope': scope, 'p_id': id},
    );
    if (actor != client.auth.currentUser?.id ||
        !ClientSyncRuntime.isCurrentMutationContext(token)) {
      throw const MemberAccessFailure('scope_denied');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<void> revoke(String invitation) => client.rpc(
    'revoke_access_invitation',
    params: {'p_invitation': invitation},
  );
  Future<Map<String, dynamic>> resend(String invitation) async {
    final request = Map<String, dynamic>.from(
      await client.rpc(
        'resend_access_invitation',
        params: {'p_invitation': invitation},
      ),
    );
    return send(request);
  }
}
