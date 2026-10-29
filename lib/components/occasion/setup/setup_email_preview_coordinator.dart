import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'setup_draft_conflict.dart';

/// An identity captured by the existing save owner, after its flush completes.
class SetupPreviewRevision {
  const SetupPreviewRevision(this.id, this.revision);
  final String id;
  final int revision;
}

class SetupEmailPreviewRequest {
  const SetupEmailPreviewRequest(
    this.draft,
    this.messageType,
    this.deliveryMode,
    this.sampleTicketCount,
  );
  final SetupPreviewRevision draft;
  final String messageType;
  final String? deliveryMode;
  final int sampleTicketCount;
  String get key =>
      '${draft.id}/${draft.revision}/$messageType/$deliveryMode/$sampleTicketCount';
  Map<String, dynamic> get rpcParams => {
    'p_id': draft.id,
    'p_expected_revision': draft.revision,
    'p_message_type': messageType,
    'p_occasion': null,
    'p_delivery_mode': deliveryMode,
  };
  Map<String, dynamic> get edgeBody => {
    'draftId': draft.id,
    'revision': draft.revision,
    'messageType': messageType,
    'sampleTicketCount': sampleTicketCount,
    if (deliveryMode != null) 'deliveryMode': deliveryMode,
  };
}

class SetupPreviewSuperseded implements Exception {}

/// Shares only in-flight reads. No saves, persistent cache or automatic retries.
class SetupEmailPreviewCoordinator {
  SetupEmailPreviewCoordinator({
    required this.confirmRevision,
    required this.read,
    required this.onConflict,
  });
  factory SetupEmailPreviewCoordinator.forClient(
    SupabaseClient client, {
    required Future<SetupPreviewRevision> Function() confirmRevision,
    required void Function() onConflict,
  }) => SetupEmailPreviewCoordinator(
    confirmRevision: confirmRevision,
    onConflict: onConflict,
    read: (request) async {
      if (request.messageType == 'order_tickets') {
        final data = await client.rpc(
          'get_occasion_setup_email_preview',
          params: request.rpcParams,
        );
        return Map<String, dynamic>.from(data as Map);
      }
      final response = await client.functions.invoke(
        'occasion-setup-email-preview',
        body: request.edgeBody,
      );
      return Map<String, dynamic>.from(response.data as Map);
    },
  );

  final Future<SetupPreviewRevision> Function() confirmRevision;
  final Future<Map<String, dynamic>> Function(SetupEmailPreviewRequest) read;
  final void Function() onConflict;
  final _pending = <String, Future<Map<String, dynamic>>>{};
  int _generation = 0;
  bool _disposed = false;

  void invalidate() => _generation++;
  void dispose() {
    _disposed = true;
    invalidate();
  }

  Future<Map<String, dynamic>> load(Map<String, dynamic> snapshot) async {
    final generation = _generation;
    // Capture parameters before crossing any asynchronous boundary.
    final message =
        snapshot['previewMessageType'] as String? ?? 'order_confirmation';
    final delivery = message == 'order_tickets'
        ? ((snapshot['ticketDraft'] as Map?)?['delivery_mode'] as String? ??
              'pdf_attachment')
        : null;
    final count = snapshot['previewTicketCount'] as int? ?? 1;
    void checkCurrent() {
      if (_disposed || generation != _generation) {
        throw SetupPreviewSuperseded();
      }
    }

    final draft = await confirmRevision();
    checkCurrent();
    final request = SetupEmailPreviewRequest(draft, message, delivery, count);
    final operation = _pending.putIfAbsent(request.key, () async {
      try {
        return await Future.sync(() => read(request));
      } catch (error) {
        if (!_disposed &&
            generation == _generation &&
            (isSetupDraftConflict(error) ||
                error is FunctionException && error.status == 409)) {
          onConflict();
        }
        rethrow;
      } finally {
        _pending.remove(request.key);
      }
    });
    final result = await operation;
    checkCurrent();
    return result;
  }
}
