import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/email_template_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

Map<String, dynamic> receipt(
  Map<String, dynamic> p, {
  int code = 200,
  String status = 'applied',
}) => {
  'code': code,
  'status': status,
  'mutation': {
    'commandId': p['p_command_id'],
    'receiptId': p['p_command_id'],
    'commitId': null,
    'replayed': false,
    'occurredAt': '2026-10-26T12:00:00Z',
  },
  'data': {
    'templates': [
      {'id': 10, 'revision': 'b' * 64},
    ],
  },
  'sync': {'replacements': []},
};

void main() {
  test('lost save response retries the original scope, revision, null values and UUID', () async {
    final calls = <Map<String, dynamic>>[];
    final commands = EmailTemplateCommands.withTransport(
      ClientCommandTransport((name, p) async {
        expect(name, 'manage_email_template');
        calls.add({...p});
        if (calls.length == 1) throw TimeoutException('Lost response');
        return receipt(p);
      }),
    );
    final stored = await commands.change(
      entityType: 'unit',
      entityId: 8,
      organizationId: 3,
      unitId: 8,
      code: 'TICKET_ORDER_CONFIRMATION',
      expectedRevision: 'a' * 64,
      action: 'save',
      payload: {'title': null, 'subject': 'Subject', 'html': ''},
    );
    expect(stored['id'], 10);
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls[0]['p_expected_revision'], 'a' * 64);
    expect(calls[0]['p_payload'], {
      'title': null,
      'subject': 'Subject',
      'html': '',
    });
  });
  test('reset and banner conflicts retain original baseline without a read or a write retry', () async {
    final calls = <String>[];
    final commands = EmailTemplateCommands.withTransport(
      ClientCommandTransport((name, p) async {
        calls.add(name);
        return receipt(p, code: 409, status: 'conflict');
      }),
    );
    await expectLater(
      commands.change(
        entityType: 'occasion',
        entityId: 42,
        organizationId: 3,
        unitId: 8,
        code: 'TICKET_ORDER_CONFIRMATION',
        expectedRevision: 'a' * 64,
        action: 'reset',
      ),
      throwsStateError,
    );
    await expectLater(
      commands.banner(
        entityType: 'occasion',
        entityId: 42,
        organizationId: 3,
        unitId: 8,
        expectedRevision: 'a' * 64,
        bannerUrl: null,
      ),
      throwsStateError,
    );
    expect(calls, ['manage_email_template', 'manage_email_banner']);
  });
}
