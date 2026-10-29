import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/occasion/setup/setup_email_preview_coordinator.dart';
import 'package:fstapp/components/occasion/setup/setup_draft_conflict.dart';

void main() {
  test('two consumers share a confirmed read; message, mode and count stay distinct', () async {
    var reads = 0;
    final gate = Completer<Map<String, dynamic>>();
    final requests = <SetupEmailPreviewRequest>[];
    final coordinator = SetupEmailPreviewCoordinator(
      confirmRevision: () async => const SetupPreviewRevision('draft', 7),
      read: (request) {
        reads++;
        requests.add(request);
        return gate.future;
      },
      onConflict: () => fail('Unexpected conflict'),
    );
    final params = <String, dynamic>{
      'previewMessageType': 'order_tickets',
      'ticketDraft': {'delivery_mode': 'both'},
    };
    final first = coordinator.load(params);
    final same = coordinator.load(params);
    final confirmation = coordinator.load({});
    final sample = coordinator.load({...params, 'previewTicketCount': 3});
    final mode = coordinator.load({
      ...params,
      'ticketDraft': {'delivery_mode': 'inline_qr'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(reads, 4);
    expect(requests.first.rpcParams['p_expected_revision'], 7);
    expect(requests.first.rpcParams['p_delivery_mode'], 'both');
    gate.complete({'subject': 'saved'});
    expect(await first, await same);
    await Future.wait([confirmation, sample, mode]);
    await coordinator.load(params);
    expect(reads, 5, reason: 'No completed read is cached');
  });
  test('edit during a delayed preview discards its result and parameters are detached', () async {
    final gate = Completer<Map<String, dynamic>>();
    final saved = Completer<SetupPreviewRevision>();
    SetupEmailPreviewRequest? captured;
    final coordinator = SetupEmailPreviewCoordinator(
      confirmRevision: () => saved.future,
      read: (r) {
        captured = r;
        return gate.future;
      },
      onConflict: () {},
    );
    final input = <String, dynamic>{
      'previewMessageType': 'order_tickets',
      'ticketDraft': {'delivery_mode': 'both'},
    };
    final result = coordinator.load(input);
    input['ticketDraft']['delivery_mode'] = 'inline_qr';
    saved.complete(const SetupPreviewRevision('draft', 3));
    await Future<void>.delayed(Duration.zero);
    expect(captured!.deliveryMode, 'both');
    coordinator.invalidate();
    final stale = expectLater(result, throwsA(isA<SetupPreviewSuperseded>()));
    gate.complete({'subject': 'old'});
    await stale;
  });
  for (final code in ['40001', 'PT409']) {
    test(
      '$code conflict terminates once; explicit retry confirms a new saved revision',
      () async {
        var reads = 0, confirms = 0, conflicts = 0;
        final coordinator = SetupEmailPreviewCoordinator(
          confirmRevision: () async =>
              SetupPreviewRevision('draft', ++confirms),
          read: (r) async {
            if (++reads == 1)
              throw PostgrestException(
                code: code,
                message: 'Draft revision conflict',
              );
            return {'revision': r.draft.revision};
          },
          onConflict: () => conflicts++,
        );
        await expectLater(
          coordinator.load({}),
          throwsA(isA<PostgrestException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(reads, 1);
        expect(conflicts, 1);
        expect(await coordinator.load({}), {'revision': 2});
        expect(reads, 2);
      },
    );
  }
  test(
    'real serialization failures are not presented as an application conflict',
    () {
      expect(
        isSetupDraftConflict(
          const PostgrestException(
            code: '40001',
            message: 'could not serialize access due to concurrent update',
          ),
        ),
        false,
      );
      expect(
        isSetupDraftConflict(
          const PostgrestException(
            code: '42501',
            message: 'Draft revision conflict',
          ),
        ),
        false,
      );
    },
  );
  test('an obsolete read conflict cannot freeze a newer local edit', () async {
    final gate = Completer<Map<String, dynamic>>();
    var conflicts = 0;
    final coordinator = SetupEmailPreviewCoordinator(
      confirmRevision: () async => const SetupPreviewRevision('draft', 1),
      read: (_) => gate.future,
      onConflict: () => conflicts++,
    );
    final result = coordinator.load({});
    await Future<void>.delayed(Duration.zero);
    coordinator.invalidate();
    final failed = expectLater(result, throwsA(isA<PostgrestException>()));
    gate.completeError(
      const PostgrestException(
        code: 'PT409',
        message: 'Draft revision conflict',
      ),
    );
    await failed;
    expect(conflicts, 0);
  });
  test(
    'the existing SDK surfaces a new PT409 once to an older direct RPC caller',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'http://127.0.0.1:56921',
        'local-key',
        httpClient: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({
              'code': 'PT409',
              'message': 'Draft changed in another session',
              'details': null,
              'hint': null,
            }),
            409,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await expectLater(
        client.rpc('save_occasion_setup_draft'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PT409'),
        ),
      );
      expect(requests, 1);
      await client.dispose();
    },
  );
}
