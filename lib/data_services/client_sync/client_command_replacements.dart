import 'package:festapp_core/sync.dart';
import 'client_sync_runtime.dart';

Future<void> applyClientCommandReplacements(
  ClientCommandResponse response, {
  bool notifyProjection = true,
  String? expectedContextToken,
}) async {
  for (final replacement in response.replacements) {
    final component =
        ClientSyncComponentWireName.parse(replacement['component'] as String);
    final revision = (replacement['revision'] as num).toInt();
    if (component == ClientSyncComponent.livePublic) {
      await ClientSyncRuntime.applyLiveReplacement(
        revision: revision,
        payload: replacement['payload'],
        notifyProjection: notifyProjection,
        expectedContextToken: expectedContextToken,
      );
    } else if (component.isPrivate) {
      await ClientSyncRuntime.applyPrivateReplacement(
        component: component,
        revision: revision,
        payload: replacement['payload'],
        notifyProjection: notifyProjection,
        expectedContextToken: expectedContextToken,
      );
    } else {
      await ClientSyncRuntime.applyPublicReplacement(
        component: component,
        revision: revision,
        payload: replacement['payload'],
        notifyProjection: notifyProjection,
        expectedContextToken: expectedContextToken,
      );
    }
  }
}
