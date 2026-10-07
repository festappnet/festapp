import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

enum InformationCommandStatus { applied, unchanged, rejected, conflict }

class InformationCommandResult {
  const InformationCommandResult({
    required this.status,
    required this.version,
    this.information,
  });

  final InformationCommandStatus status;
  final int version;
  final InformationModel? information;
}

class GameGuessCommandResult {
  const GameGuessCommandResult({
    required this.status,
    required this.domainCode,
    required this.correct,
  });

  final InformationCommandStatus status;
  final int domainCode;
  final bool correct;
}

abstract interface class InformationCommands {
  Future<InformationCommandResult> save(
      int occasionId, InformationModel information);
  Future<InformationCommandResult> delete(
      int occasionId, InformationModel information);
  Future<GameGuessCommandResult> guess(int checkpointId, String guess);
}

class SupabaseInformationCommands implements InformationCommands {
  SupabaseInformationCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client),
        _actorId = (() => client.auth.currentUser?.id);

  SupabaseInformationCommands.withTransport(this._transport)
      : _actorId = (() => null);

  final ClientCommandTransport _transport;
  final String? Function() _actorId;

  @override
  Future<GameGuessCommandResult> guess(int checkpointId, String guess) async {
    final actor = _actorId();
    final token = ClientSyncRuntime.mutationContextToken;
    final response = ClientCommandResponse.from(
      await _transport.invokeIntent(
          '$actor:$checkpointId:game.guess', 'game_guess_client_sync_v1', {
        'p_checkpoint': checkpointId,
        'p_guess': guess,
      }),
    );
    if (actor == _actorId()) {
      await response.applyConfirmedReplacements(expectedContextToken: token);
    }
    return GameGuessCommandResult(
      status: InformationCommandStatus.values.byName(response.status),
      domainCode: (response.data['domainCode'] as num?)?.toInt() ?? 500,
      correct: response.data['correct'] == true,
    );
  }

  @override
  Future<InformationCommandResult> save(
      int occasionId, InformationModel information) async {
    final raw = await _transport.invoke('save_information_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version':
          information.id == null ? null : information.aggregateVersion,
      'p_information': {
        if (information.id case final id?) 'id': id,
        'title': information.title,
        'description': information.description,
        'type': information.type,
        'isHidden': information.isHidden ?? false,
        'order': information.order,
        'data': information.data,
        'hiddenData': information.type == InformationModel.gameType
            ? information.informationHidden?.data
            : null,
      },
    });
    return _decode(raw);
  }

  @override
  Future<InformationCommandResult> delete(
      int occasionId, InformationModel information) async {
    final id = information.id;
    if (id == null) {
      throw ArgumentError('Deleting information requires its ID');
    }
    return _decode(
        await _transport.invoke('delete_information_client_sync_v1', {
      'p_occasion': occasionId,
      'p_information_id': id,
      'p_expected_version': information.aggregateVersion,
    }));
  }

  Future<InformationCommandResult> _decode(Object? raw) async {
    final response = ClientCommandResponse.from(raw);
    await response.applyReplacements();
    final data = response.data;
    final version = (data['version'] as num?)?.toInt() ?? 0;
    final entity = data['information'];
    return InformationCommandResult(
      status: InformationCommandStatus.values.byName(response.status),
      version: version,
      information: entity is Map
          ? InformationModel.fromJson({
              ...entity.cast<String, dynamic>(),
              'aggregate_version': version,
            })
          : null,
    );
  }
}
