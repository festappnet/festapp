import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/blueprint/seating_transition_controller.dart';
import 'package:fstapp/components/blueprint/seating_transition_models.dart';
import 'package:fstapp/components/blueprint/seating_transition_panel.dart';
import 'package:fstapp/components/blueprint/seating_transition_transport.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

import '../../support/fixtures/client_command_response_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

Map<String, dynamic> contextData({
  bool read = true,
  bool assign = true,
  bool configure = true,
  int unassigned = 9,
  int waiting = 1,
  List<Map<String, dynamic>>? items,
}) => {
  'transitionId': 't1',
  'blueprintId': 10,
  'revision': 1,
  'state': 'organizer_managed',
  'capabilities': {
    'readHolders': read,
    'assign': assign,
    'configure': configure,
  },
  'counts': {
    'unassigned': unassigned,
    'assigned': 9 - unassigned,
    'standing': 0,
    'blocked': 0,
    'waiting': waiting,
    'offered': 0,
  },
  'items': read ? items ?? [admission(1), admission(2, form: 21)] : [],
  'seats': [
    for (var n = 1; n <= 2; n++)
      {
        'id': n + 100,
        'title': 'Seat $n',
        'productId': 5,
        'available': true,
        'unitSpotIds': [101, 102],
      },
  ],
  'compatibility': [],
  'cohort': [],
  'nextCursor': null,
  'publicationAvailable': configure,
};
Map<String, dynamic> admission(int id, {int form = 20}) => {
  'ticketId': id,
  'admissionItemId': id + 10,
  'orderId': id + 30,
  'formId': form,
  'productId': 5,
  'productTitle': 'Admission',
  'holder': 'Holder $id',
  'category': 'unassigned',
  'spotId': null,
};

class Fixture {
  Map<String, dynamic> data = contextData();
  final calls = <Map<String, dynamic>>[];
  Future<Object?> Function(String, Map<String, dynamic>)? mutate;
  late final transport = SeatingTransitionTransport.withTransport(
    read,
    ClientCommandTransport((name, params) async {
      calls.add({'name': name, ...params});
      return mutate == null
          ? commandResponseFixture(params['p_command_id'] as String)
          : await mutate!(name, params);
    }, maxAttempts: 1),
  );
  late final controller = SeatingTransitionController(
    transport: transport,
    occasionId: 1,
    blueprintId: 10,
  );
  Future<Object?> read(String name, Map<String, dynamic> params) async {
    if (name == 'get_seating_workspace')
      return {
        'code': 200,
        'data': {
          'transitions': [
            {'id': 't1', 'blueprintId': 10, 'state': 'organizer_managed'},
          ],
          'forms': [],
          'capabilities': data['capabilities'],
        },
      };
    if (name == 'get_seating_transition_context')
      return {'code': 200, 'data': data};
    if (name == 'preview_ticket_seat_assignment')
      return {
        'code': 200,
        'data': {
          'fingerprint': 'exact-preview',
          'mappings': params['p_mappings'],
          'blockers': [],
        },
      };
    throw StateError(name);
  }
}

void main() {
  WidgetEnvironmentFixture.register();
  test(
    'nine assigned and one waiting is a complete organizer-managed outcome',
    () {
      final context = SeatingContext(contextData(unassigned: 0));
      expect(context.allAssigned, isTrue);
      expect(context.counts['waiting'], 1);
      expect(context.admitted, 9);
    },
  );
  test(
    'ambiguous legacy admission identifiers remain visible and unselectable',
    () {
      final item = SeatingAdmission({
        ...admission(1),
        'admissionItemId': null,
        'productId': null,
        'category': 'blocked',
        'reason': 'ADMISSION_DATA_AMBIGUOUS',
      });
      expect(item.mutable, isFalse);
      expect(item.ticketId, 1);
    },
  );
  test(
    'cross-form unit requires explicit unique ticket-to-seat draft pairs',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.controller.load(discover: true);
      f.controller.select(f.controller.context!.items.first);
      f.controller.pair(101);
      f.controller.select(f.controller.context!.items.last);
      expect(f.controller.compatible.map((s) => s.id), [102]);
      f.controller.pair(102);
      expect(f.controller.pairs.values.map((p) => p.toJson()).toList(), [
        {
          'ticketId': 1,
          'admissionItemId': 11,
          'expectedSpotId': null,
          'targetSpotId': 101,
        },
        {
          'ticketId': 2,
          'admissionItemId': 12,
          'expectedSpotId': null,
          'targetSpotId': 102,
        },
      ]);
      expect(f.controller.pairAdmissions.values.map((i) => i.formId), [20, 21]);
    },
  );
  test(
    'timeout blocks editing and replays the exact command identity',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.controller.load(discover: true);
      f.controller.select(f.controller.context!.items.first);
      f.controller.pair(101);
      final preview = await f.controller.preview();
      f.mutate = (_, __) async =>
          throw TimeoutException('unknown commit result');
      expect(await f.controller.commit(preview!), isFalse);
      expect(f.controller.uncertain, isTrue);
      f.controller.remove(11);
      expect(f.controller.pairs, hasLength(1));
      f.mutate = (_, params) async =>
          commandResponseFixture(params['p_command_id'] as String);
      expect(await f.controller.recover(), isTrue);
      expect(f.calls[0], f.calls[1]);
      expect(f.controller.pairs, isEmpty);
    },
  );
  test('couch-first selection requests explicit admissions without inventing pairs', () async {
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.controller.load(discover: true);
    f.controller.pair(101);
    expect(f.controller.requestedUnit, {101, 102});
    expect(f.controller.pairs, isEmpty);
    f.controller.select(f.controller.context!.items.first);
    f.controller.pair(101);
    expect(f.controller.requestedUnit, {101, 102});
    f.controller.select(f.controller.context!.items.last);
    f.controller.pair(102);
    expect(f.controller.requestedUnit, isEmpty);
    expect(f.controller.pairs, hasLength(2));
  });
  test('terminal conflict retains draft and requires a new review', () async {
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.controller.load(discover: true);
    f.controller.select(f.controller.context!.items.first);
    f.controller.pair(101);
    f.mutate = (_, params) async => commandResponseFixture(
      params['p_command_id'] as String,
      status: 'rejected',
      code: 409,
      data: {'reason': 'CONTEXT_CHANGED'},
    );
    expect(await f.controller.commit((await f.controller.preview())!), isFalse);
    expect(f.controller.uncertain, isFalse);
    expect(f.controller.pairs, hasLength(1));
    expect(f.controller.error, 'CONTEXT_CHANGED');
  });
  test(
    'order-only operator assigns without configuration capability',
    () async {
      final f = Fixture()..data = contextData(configure: false);
      addTearDown(f.controller.dispose);
      await f.controller.load(discover: true);
      expect(f.controller.canAssign, isTrue);
      expect(f.controller.context!.publicationAvailable, isFalse);
    },
  );
  test(
    'identity invalidation removes holders and local drafts immediately',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.controller.load(discover: true);
      f.controller.select(f.controller.context!.items.first);
      f.controller.pair(101);
      f.controller.invalidateIdentity();
      expect(f.controller.context, isNull);
      expect(f.controller.pairAdmissions, isEmpty);
      expect(f.controller.pairs, isEmpty);
    },
  );
  test('duplicate submit shares one flight', () async {
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.controller.load(discover: true);
    f.controller.select(f.controller.context!.items.first);
    f.controller.pair(101);
    final preview = (await f.controller.preview())!;
    final gate = Completer<Object?>();
    f.mutate = (_, __) => gate.future;
    final first = f.controller.commit(preview);
    expect(await f.controller.commit(preview), isFalse);
    expect(f.calls, hasLength(1));
    gate.complete(
      commandResponseFixture(f.calls.single['p_command_id'] as String),
    );
    expect(await first, isTrue);
  });
  testWidgets('summary keeps waiting separate from all-assigned success', (
    tester,
  ) async {
    final f = Fixture()..data = contextData(unassigned: 0);
    addTearDown(f.controller.dispose);
    await f.controller.load(discover: true);
    final env = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: {
        'SeatingTransition': {
          'allAssigned': 'All assigned',
          'unassigned': 'Unassigned',
          'waiting': 'Waiting',
          'offered': 'Offered',
          'open': 'Assign seats',
        },
      },
    );
    await env.pumpWidget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: SeatingTransitionSummary(
            controller: f.controller,
            open: () {},
            onWaitlist: () {},
          ),
        ),
      ),
    );
    expect(find.text('All assigned'), findsOneWidget);
    expect(find.text('Waiting: 1 · Offered: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mobile workspace keeps the queue visible below the canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 700,
            child: SeatingWorkspaceFrame(
              active: true,
              panel: Text('Admission queue'),
              child: Text('Saved plan'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Admission queue'), findsOneWidget);
    expect(find.text('Saved plan'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Admission queue')).dy,
      greaterThan(tester.getTopLeft(find.text('Saved plan')).dy),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saved-plan guard preserves cancel and explicitly saves or discards',
    (tester) async {
      var dirty = true;
      var saves = 0;
      var discards = 0;
      bool? result;
      final env = WidgetEnvironmentFixture(
        locale: const Locale('en'),
        translations: {
          'Common': {
            'save': 'Save',
            'cancel': 'Cancel',
            'discardChanges': 'Discard changes',
            'close': 'Close',
          },
          'SeatingTransition': {
            'saveDraft': 'Save layout?',
            'saveDraftDetail': 'Use the saved plan',
          },
        },
      );
      await env.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await confirmSeatingSavedPlan(
                    context,
                    isDirty: () => dirty,
                    save: () async {
                      saves++;
                      dirty = false;
                    },
                    discard: () {
                      discards++;
                      dirty = false;
                    },
                  );
                },
                child: const Text('Open seating'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open seating'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(dirty, isTrue);
      expect(saves + discards, 0);
      await tester.tap(find.text('Open seating'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(discards, 1);
      expect(saves, 0);
      dirty = true;
      await tester.tap(find.text('Open seating'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(saves, 1);
      expect(dirty, isFalse);
    },
  );
  testWidgets(
    'assignment review Cancel and Escape dismiss without changing draft',
    (tester) async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.controller.load(discover: true);
      f.controller.select(f.controller.context!.items.first);
      f.controller.pair(101);
      final env = WidgetEnvironmentFixture(
        locale: const Locale('en'),
        translations: {
          'Common': {'cancel': 'Cancel', 'close': 'Close'},
          'SeatingTransition': {
            'review': 'Review assignments',
            'reviewTitle': 'Confirm exact assignments',
            'confirm': 'Assign reviewed seats',
          },
        },
      );
      await env.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: SeatingTransitionPanel(
                controller: f.controller,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Review assignments'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Review assignments'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm exact assignments'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm exact assignments'), findsNothing);
      expect(f.controller.pairs, hasLength(1));
      expect(f.calls, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Review assignments'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Review assignments'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Confirm exact assignments'), findsNothing);
      expect(f.controller.pairs, hasLength(1));
      expect(f.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  test('own assignment keeps confirmation notice; new admissions show changed worklist', () async {
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.controller.load(discover: true);
    f.controller.select(f.controller.context!.items.first);
    f.controller.pair(101);
    final preview = (await f.controller.preview())!;
    f.mutate = (_, params) async {
      f.data = contextData(unassigned: 8);
      return commandResponseFixture(params['p_command_id'] as String);
    };
    expect(await f.controller.commit(preview), isTrue);
    expect(f.controller.notice, 'saved');
    final counts = f.data['counts'] as Map<String, dynamic>;
    counts['unassigned'] = 9;
    await f.controller.load();
    expect(f.controller.notice, 'changed');
  });

  testWidgets(
    'existing public plan never advertises unsupported configuration start',
    (tester) async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.controller.workspace = {
        'status': 'published',
        'capabilities': {'configure': true},
        'forms': [
          {
            'id': 20,
            'title': 'Existing form',
            'canStart': false,
            'reason': 'TARGET_ALREADY_PUBLIC',
          },
        ],
      };
      final env = WidgetEnvironmentFixture(
        locale: const Locale('en'),
        translations: {
          'SeatingTransition': {
            'published': 'Public seat selection is active.',
            'start': 'Use this form',
          },
        },
      );
      await env.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SeatingTransitionSummary(controller: f.controller, open: () {}),
                Expanded(
                  child: SeatingTransitionPanel(
                    controller: f.controller,
                    onClose: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('seating-summary')), findsNothing);
      expect(find.text('Public seat selection is active.'), findsOneWidget);
      expect(find.text('Use this form'), findsNothing);
    },
  );
}
