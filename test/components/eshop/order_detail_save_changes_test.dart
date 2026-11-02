import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/order_detail_controller.dart';
import 'package:fstapp/components/eshop/order_commands.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

import '../../support/fixtures/localization_log_fixture.dart';

class _ContactCommands extends Fake implements OrderCommands {
  _ContactCommands(this.apply);
  final void Function(String) apply;
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> repairEmail({
    required int orderId,
    required String expectedEmail,
    required String expectedState,
    required int expectedPaymentVersion,
    required String expectedPaymentFingerprint,
    required String email,
    String? sourceMessageId,
    required bool resend,
    String? commandId,
  }) async {
    calls.add({
      'order': orderId,
      'expected': expectedEmail,
      'email': email,
      'resend': resend,
      'version': expectedPaymentVersion,
      'fingerprint': expectedPaymentFingerprint,
    });
    apply(email);
    return {'code': 200};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OccasionLinkModel? previous;
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
    previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: OccasionModel(
        id: 71,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
      ),
    );
  });
  tearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  Map<String, dynamic> record() => {
    'order': {
      'id': 42,
      'occasion': 71,
      'state': 'ordered',
      'allowedActions': ['edit'],
      'email_payment_version': 3,
      'email_payment_fingerprint': 'current',
      'data': {'email': 'old@example.invalid'},
    },
    'capabilities': {'write': true},
    'answers': [
      {'1': 'Original phone'},
      {'2': 'Original company'},
    ],
  };
  test(
    'global save advances fences and retries only drafts not yet confirmed',
    () async {
      final data = record();
      var reads = 0;
      var first = true;
      var second = true;
      var reject = true;
      final calls = <String>[];
      final controller = OrderDetailController(
        orderId: 42,
        occasionId: 71,
        read: (_, __) async {
          reads++;
          return {'code': 200, 'data': jsonDecode(jsonEncode(data))};
        },
      );
      addTearDown(controller.dispose);
      expect(await controller.load(), isTrue);
      controller.registerInlineDraft(
        'phone',
        isDirty: () => first,
        discard: () => first = false,
        save: () async {
          calls.add('phone');
          data['answers'] = [
            {'1': 'New phone'},
            {'2': 'Original company'},
          ];
          first = false;
        },
      );
      controller.registerInlineDraft(
        'company',
        isDirty: () => second,
        discard: () => second = false,
        save: () async {
          expect(controller.detail!.json['answers'], [
            {'1': 'New phone'},
            {'2': 'Original company'},
          ]);
          if (reject) throw StateError('Temporary failure');
          calls.add('company');
          data['answers'] = [
            {'1': 'New phone'},
            {'2': 'New company'},
          ];
          second = false;
        },
      );
      await expectLater(controller.saveDrafts(), throwsStateError);
      expect(calls, ['phone']);
      expect(reads, 2);
      expect(controller.dirtyDraftCount, 1);
      expect(controller.busy, isFalse);
      reject = false;
      await controller.saveDrafts();
      expect(calls, ['phone', 'company']);
      expect(reads, 3);
      expect(controller.dirty, isFalse);
    },
  );
  test('global contact save uses the existing repair owner without enqueueing email', () async {
    final data = record();
    final commands = _ContactCommands((email) {
      data['order']['data']['email'] = email;
    });
    final controller = OrderDetailController(
      orderId: 42,
      occasionId: 71,
      commands: commands,
      read: (_, __) async => {
        'code': 200,
        'data': jsonDecode(jsonEncode(data)),
      },
    );
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    controller.email.text = 'new@example.invalid';
    expect(controller.dirtyDraftCount, 1);
    await controller.saveDrafts();
    expect(commands.calls, [
      {
        'order': 42,
        'expected': 'old@example.invalid',
        'email': 'new@example.invalid',
        'resend': false,
        'version': 3,
        'fingerprint': 'current',
      },
    ]);
    expect(controller.email.text, 'new@example.invalid');
    expect(controller.dirty, isFalse);
  });
}
