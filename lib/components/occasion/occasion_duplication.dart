import 'dart:convert';

import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'occasion_commands.dart';

/// One database copy followed by resumable deterministic Worker media effects.
class OccasionDuplicator {
  OccasionDuplicator({
    required this.commands,
    required this.completeMedia,
    this.principalBinding,
  });
  final String Function()? principalBinding;
  final OccasionCommands commands;
  final Future<void> Function(String commandId) completeMedia;
  Future<({int occasionId, bool mediaCopied})> duplicate(
    int source, {
    int? targetUnitId,
    String locale = 'en',
    String? commandId,
  }) async {
    final principal = principalBinding?.call();
    final payload = {
      'source': source,
      'targetUnitId': targetUnitId,
      'locale': locale,
    };
    final namespace = '$principal:occasion.copy.media';
    final ownsIntent = commandId == null && principal != null;
    final intent =
        commandId ??
        (ownsIntent
            ? await ClientCommandIdentity.claimIntent(
                namespace,
                payload,
                principalBinding: principal,
                scopeBinding: '$source:$targetUnitId',
                requestJson: jsonEncode(payload),
              )
            : const Uuid().v4());
    if (principal != null && principalBinding?.call() != principal) {
      throw StateError('Copy identity changed');
    }
    final id = await commands.duplicate(
      source,
      targetUnitId: targetUnitId,
      locale: locale,
      commandId: intent,
    );
    if (principal != null && principalBinding?.call() != principal) {
      throw StateError('Copy identity changed');
    }
    try {
      await completeMedia(intent);
      if (ownsIntent) {
        if (principalBinding?.call() != principal) {
          throw StateError('Copy identity changed');
        }
        await ClientCommandIdentity.completeIntent(
          namespace,
          payload,
          commandId: intent,
          principalBinding: principal,
        );
      }
      return (occasionId: id, mediaCopied: true);
    } catch (_) {
      if (principal != null && principalBinding?.call() != principal) {
        rethrow;
      }
      debugPrint('Occasion $id exists; resume media job $intent.');
      return (occasionId: id, mediaCopied: false);
    }
  }
}
