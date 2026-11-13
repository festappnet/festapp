import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';

void main() {
  test('email settings save only current self scope and refresh authoritative revision', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    var revision = 4;
    final controller = NotificationCenterController(
      read: (name, params) async {
        calls.add((name, Map<String, dynamic>.from(params)));
        if (name == 'save_notification_center_email_settings') {
          expect(params.containsKey('recipient'), false);
          expect(params['p_revision'], 4);
          expect(params.containsKey('p_occasion'), false);
          revision++;
          return revision;
        }
        return {
          'items': [],
          'email': {
            'revision': revision,
            'stopped': false,
            'catalog': {'order_created': 'orders'},
          },
        };
      },
    );
    controller.organization = 7;
    controller.user = 'current-user';
    controller.enabled = true;
    await controller.loadSettings();
    expect(
      await controller.saveEmailSettings(
        stopped: false,
        locale: 'cs',
        kinds: {'order_created': true},
      ),
      true,
    );
    expect(controller.emailSettings['revision'], 5);
    expect(
      calls
          .where((call) => call.$1 == 'save_notification_center_email_settings')
          .length,
      1,
    );
    controller.dispose();
  });
  test('failed save keeps revision and always releases saving state', () async {
    final controller = NotificationCenterController(
      read: (name, params) async => throw StateError('failed'),
    );
    controller.organization = 7;
    controller.user = 'current-user';
    controller.emailSettings = {'revision': 3};
    expect(
      await controller.saveEmailSettings(
        stopped: true,
        locale: 'cs',
        kinds: {},
      ),
      false,
    );
    expect(controller.emailSaving, false);
    expect(controller.emailSettings['revision'], 3);
    controller.dispose();
  });
}
