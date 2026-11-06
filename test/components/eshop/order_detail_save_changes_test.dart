import 'dart:async';

import 'package:fstapp/components/eshop/order_contact_controller.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';

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
  test('confirmed contact stays clean when readback fails and reload never resends', () async {
    final data = record();
    var failRead = false;
    final commands = _ContactCommands((email) {
      data['order']['data']['email'] = email;
      failRead = true;
    });
    final controller = OrderDetailController(
      orderId: 42,
      occasionId: 71,
      commands: commands,
      read: (_, __) async {
        if (failRead) throw StateError('readback offline');
        return {'code': 200, 'data': jsonDecode(jsonEncode(data))};
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.email.text = 'new@example.invalid';
    await expectLater(controller.saveDrafts(), throwsStateError);
    expect(controller.contact.dirty, false);
    expect(controller.contact.stale, true);
    failRead = false;
    await controller.load();
    await controller.saveDrafts();
    expect(commands.calls, hasLength(1));
    expect(controller.dirty, false);
  });

  test('contact ignores a command receipt after occasion changes', () async {
    final receipt = Completer<Map<String, dynamic>>();
    final commands = _DeferredContactCommands(receipt.future);
    final controller = OrderDetailController(
      orderId: 42,
      occasionId: 71,
      commands: commands,
      read: (_, __) async => {'code': 200, 'data': record()},
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.email.text = 'new@example.invalid';
    final saving = controller.contact.save(resend: false);
    RightsService.occasionLinkModelNotifier.value = null;
    receipt.complete({'code': 200});
    await saving;
    expect(controller.contact.order, isNull);
    expect(controller.detail, isNull);
  });

  test('conflict refresh preserves the unsaved draft', () async {
    final commands = _DeferredContactCommands(Future.value({'code': 409}));
    final controller = OrderDetailController(
      orderId: 42,
      occasionId: 71,
      commands: commands,
      read: (_, __) async => {'code': 200, 'data': record()},
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.email.text = 'new@example.invalid';
    await expectLater(controller.saveDrafts(), throwsStateError);
    expect(controller.contact.dirty, true);
    expect(controller.email.text, 'new@example.invalid');
  });

  test(
    'reopened session recovers the original pending intent after discard',
    () async {
      final intent = ClientCommandIntent(
        operation: 'repair_order_email_client_sync_v1',
        commandId: '00000000-0000-4000-8000-000000000007',
        principalBinding: 'fixture',
        requestJson: jsonEncode({
          'p_order': 42,
          'p_email': 'pending@example.invalid',
          'p_resend': false,
        }),
      );
      final commands = _PendingContactCommands(intent);
      OrderContactController session() => OrderContactController(
        orderId: 42,
        occasionId: 71,
        commands: commands,
        read: (_, __) async => null,
        validContext: () => true,
        loadSnapshot: () async => {
          'order': record()['order'],
          'emailSummary': <String, dynamic>{},
        },
      );
      final first = session();
      await first.load();
      first.email.text = 'discarded@example.invalid';
      first.discard();
      first.dispose();
      final reopened = session();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.pendingContact, same(intent));
      await expectLater(reopened.ensureNoPending(), throwsStateError);
      await reopened.recover();
      expect(commands.recovered, same(intent));
      expect(reopened.pendingContact, isNull);
    },
  );
  test('global inline save cannot bypass a retained contact intent after discard', () async {
    final commands = _PendingContactCommands(ClientCommandIntent(
      operation:'repair_order_email_client_sync_v1', commandId:'00000000-0000-4000-8000-000000000007',
      principalBinding:'fixture',requestJson:jsonEncode({'p_email':'pending@example.invalid'})));
    final controller = OrderDetailController(orderId:42,occasionId:71,commands:commands,
      read:(_,__)async=>{'code':200,'data':record()});
    addTearDown(controller.dispose);
    await controller.load();
    controller.discardDraft();
    var saved=false;
    controller.registerInlineDraft('phone',isDirty:()=>true,discard:(){},save:()async{saved=true;});
    await expectLater(controller.saveDrafts(),throwsStateError);
    expect(saved,false);
    expect(commands.pending,isNotNull);
  });

}

class _DeferredContactCommands extends Fake implements OrderCommands {
  _DeferredContactCommands(this.response);
  final Future<Map<String, dynamic>> response;
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
  }) => response;
}

class _PendingContactCommands extends _ContactCommands
    implements RecoverableOrderContactCommands {
  _PendingContactCommands(this.pending) : super((_) {});
  ClientCommandIntent? pending, recovered;
  @override
  Future<ClientCommandIntent?> pendingContact(int orderId) async => pending;
  @override
  Future<Map<String, dynamic>> recoverContact(
    ClientCommandIntent intent,
  ) async {
    recovered = intent;
    pending = null;
    return {'code': 200};
  }
}
