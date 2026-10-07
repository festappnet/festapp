import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

/// Parsed standard response shared by all typed domain command adapters.
/// Domain adapters still own DTOs and result types; this module owns only the
/// mutation protocol envelope and cache replacement activation.
class ClientCommandResponse {
  const ClientCommandResponse({
    required this.status,
    required this.code,
    required this.data,
    required this.replacements,
    required this.mutation,
  });

  final Map<String, dynamic> mutation;
  static String? _activationContext;
  static final Map<String, String> _activated = {};
  static final Map<String, bool> _unnotified = {};
  static final Map<String, String> _commandRevisionDigests = {};
  static Future<void> _activationTail = Future.value();
  final String status;
  final int code;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> replacements;

  factory ClientCommandResponse.from(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid client command response');
    }
    final response = raw.cast<String, dynamic>();
    final status = response['status'];
    final code = response['code'];
    final data = response['data'];
    final sync = response['sync'];
    final mutation = response['mutation'];
    final uuid =
        RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
    if (mutation is! Map ||
        mutation['commandId'] is! String ||
        !uuid.hasMatch(mutation['commandId']) ||
        mutation['receiptId'] != mutation['commandId'] ||
        (mutation['commitId'] != null &&
            (mutation['commitId'] is! String ||
                !uuid.hasMatch(mutation['commitId']))) ||
        mutation['replayed'] is! bool ||
        mutation['occurredAt'] is! String ||
        DateTime.tryParse(mutation['occurredAt']) == null) {
      throw const FormatException('Invalid mutation identity');
    }
    if (status is! String ||
        !const {'applied', 'unchanged', 'rejected', 'conflict'}
            .contains(status) ||
        code is! num ||
        data is! Map ||
        sync is! Map ||
        sync['replacements'] is! List) {
      throw const FormatException('Invalid client command envelope');
    }
    return ClientCommandResponse(
      mutation: mutation.cast<String, dynamic>(),
      status: status,
      code: code.toInt(),
      data: data.cast<String, dynamic>(),
      replacements: (sync['replacements'] as List)
          .map((item) => (item as Map).cast<String, dynamic>())
          .toList(growable: false),
    );
  }

  /// DB success remains authoritative when local cache activation needs repair.
  Future<bool> applyConfirmedReplacements(
      {String? expectedContextToken}) async {
    try {
      await applyReplacements(expectedContextToken: expectedContextToken);
      return true;
    } catch (error) {
      debugPrint('Committed command cache activation needs repair: $error');
      try {
        await applyReplacements(expectedContextToken: expectedContextToken);
        return true;
      } catch (error) {
        debugPrint('Receipt cache repair pending: $error');
        final token = expectedContextToken;
        if (token != null &&
            ClientSyncRuntime.isCurrentMutationContext(token)) {
          unawaited(ClientSyncRuntime.refresh(SyncReason.manual,
                  privateConsumer: true)
              .catchError((Object error) {
            debugPrint('Command projection refresh failed: $error');
          }));
        }
        return false;
      }
    }
  }

  Future<void> applyReplacements({
    bool notifyProjection = true,
    String? expectedContextToken,
    ClientCommandActivation activation = const RuntimeCommandActivation(),
  }) async {
    final token = expectedContextToken ?? activation.contextToken;
    // Legacy readers have no active command cache. Avoid joining a completed
    // activation future from another async zone when there is nothing to apply.
    if (!activation.enabled || activation.contextToken != token) return;
    final previous = _activationTail;
    final done = Completer<void>();
    _activationTail = done.future;
    try {
      await previous;
      if (activation.contextToken != token || !activation.enabled) return;
      if (_activationContext != token) {
        _activated.clear();
        _unnotified.clear();
        _commandRevisionDigests.clear();
        _activationContext = token;
      }
      for (final replacement in replacements) {
        if (activation.contextToken != token) return;
        final component = ClientSyncComponentWireName.parse(
            replacement['component'] as String);
        final revision = (replacement['revision'] as num).toInt();
        final key =
            '${mutation['receiptId']}:${replacement['component']}:$revision';
        final currentRevision = await activation.revision(component);
        if (currentRevision != null && currentRevision > revision) {
          _unnotified.remove(key);
          continue;
        }
        final revisionKey = '${replacement['component']}:$revision';
        final digest =
            ClientCommandIdentity.fingerprint(replacement['payload']);
        if (_commandRevisionDigests.containsKey(revisionKey) &&
            _commandRevisionDigests[revisionKey] != digest) {
          throw StateError('Conflicting command payload at the same revision');
        }
        if (_activated[key] == digest) {
          continue;
        }
        if (_activated.containsKey(key)) {
          throw StateError('Command replacement payload changed on replay');
        }
        if (component.isPrivate && !activation.hasPrivateIdentity) {
          continue;
        }
        await activation.apply(
            component, revision, replacement['payload'], token);
        if (activation.contextToken != token) {
          return;
        }
        final activeRevision = await activation.revision(component);
        if (activeRevision != revision) {
          continue;
        }
        _activated[key] = digest;
        _commandRevisionDigests[revisionKey] = digest;
        if (_commandRevisionDigests.length > 512) {
          _commandRevisionDigests.remove(_commandRevisionDigests.keys.first);
        }
        if (_activated.length > 512) _activated.remove(_activated.keys.first);
        _unnotified[key] = component.affectsSearchIndex;
        if (_unnotified.length > 512) {
          _unnotified.remove(_unnotified.keys.first);
        }
      }
      final pending = _unnotified.entries
          .where((e) => e.key.startsWith('${mutation['receiptId']}:'))
          .toList();
      if (pending.isNotEmpty && notifyProjection) {
        activation.notify(pending.any((e) => e.value));
        for (final entry in pending) {
          _unnotified.remove(entry.key);
        }
      }
    } finally {
      done.complete();
    }
  }
}

/// The command-only cache seam. Local same-revision patches bypass this seam.
abstract interface class ClientCommandActivation {
  String get contextToken;
  bool get enabled;
  bool get hasPrivateIdentity;
  Future<int?> revision(ClientSyncComponent component);
  Future<void> apply(ClientSyncComponent component, int revision,
      Object? payload, String token);
  void notify(bool searchIndexChanged);
}

class RuntimeCommandActivation implements ClientCommandActivation {
  const RuntimeCommandActivation();
  @override
  String get contextToken => ClientSyncRuntime.mutationContextToken;
  @override
  bool get enabled => ClientSyncRuntime.isV1Selected;
  @override
  bool get hasPrivateIdentity => ClientSyncRuntime.hasPrivateIdentity;
  @override
  Future<int?> revision(ClientSyncComponent component) =>
      ClientSyncRuntime.commandComponentRevision(component);
  @override
  Future<void> apply(ClientSyncComponent component, int revision,
      Object? payload, String token) {
    if (component == ClientSyncComponent.livePublic) {
      return ClientSyncRuntime.applyLiveReplacement(
          revision: revision,
          payload: payload,
          notifyProjection: false,
          expectedContextToken: token);
    }
    if (component.isPrivate) {
      return ClientSyncRuntime.applyPrivateReplacement(
          component: component,
          revision: revision,
          payload: payload,
          notifyProjection: false,
          expectedContextToken: token);
    }
    return ClientSyncRuntime.applyPublicReplacement(
        component: component,
        revision: revision,
        payload: payload,
        notifyProjection: false,
        expectedContextToken: token);
  }

  @override
  void notify(bool searchIndexChanged) =>
      ClientSyncRuntime.notifyCommandProjectionChanged(
          searchIndexChanged: searchIndexChanged);
}
