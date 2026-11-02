import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/eshop/order_blueprint_cache.dart';
import 'package:fstapp/components/eshop/order_detail_controller.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

Map<String, dynamic> full(int id, {int occasion = 71, int revision = 3}) => {
  'id': id,
  'occasion': occasion,
  'layout_revision': revision,
  'layout': VenueLayoutDocument.empty().toJson(),
  'resources': <String, dynamic>{},
  'seatStates': [],
  'placementFingerprint': 'current',
};
Map<String, dynamic> thin(int id, {int occasion = 71, int revision = 3}) =>
    full(id, occasion: occasion, revision: revision)
      ..remove('layout')
      ..remove('resources');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('drawings are scoped by occasion and plan; thin replies require an exact saved revision', () {
    final cache = OrderBlueprintCache();
    final original = cache.decode(full(81), occasionId: 71, blueprintId: 81);
    final known = cache.lookup(71, 81)!;
    final next = cache.decode(
      thin(81),
      occasionId: 71,
      blueprintId: 81,
      known: known,
    );
    expect(next.plan.document, same(original.plan.document));
    expect(original.data.containsKey('layout'), isFalse);
    expect(original.data.containsKey('resources'), isFalse);
    expect(() => original.data['id'] = 99, throwsUnsupportedError);
    expect(cache.lookup(72, 81), isNull);
    for (final data in [
      thin(81, revision: 4),
      thin(81, occasion: 72),
      thin(82),
    ]) {
      expect(
        () => cache.decode(data, occasionId: 71, blueprintId: 81, known: known),
        throwsFormatException,
      );
    }
    expect(
      () => cache.decode(thin(81), occasionId: 71, blueprintId: 81),
      throwsFormatException,
    );
    expect(
      () => cache.decode(
        full(81)..remove('resources'),
        occasionId: 71,
        blueprintId: 81,
        known: known,
      ),
      throwsFormatException,
    );
    final changed = cache.decode(
      full(81, revision: 4),
      occasionId: 71,
      blueprintId: 81,
      known: known,
    );
    expect(changed.plan.document, isNot(same(original.plan.document)));
    expect(cache.lookup(71, 81)!.revision, 4);
    cache.clear();
    expect(cache.lookup(71, 81), isNull);
  });

  test('cached rendering resources cannot be mutated through a raw response or viewer', () {
    final cache = OrderBlueprintCache();
    final input = full(81);
    final resources = <String, dynamic>{
      'fontFamilies': {
        'fixture': {
          'metrics': [1, 2],
        },
      },
    };
    input['resources'] = resources;
    final view = cache.decode(input, occasionId: 71, blueprintId: 81);
    (resources['fontFamilies']['fixture']['metrics'] as List)[0] = 99;
    final metrics =
        view.plan.resources['fontFamilies']['fixture']['metrics'] as List;
    expect(metrics, [1, 2]);
    expect(() => metrics[0] = 3, throwsUnsupportedError);
  });

  test('cache stays bounded and retains the exact snapshot of an in-flight authorized read', () {
    final cache = OrderBlueprintCache();
    cache.decode(full(81), occasionId: 71, blueprintId: 81);
    final known = cache.lookup(71, 81)!;
    for (final id in [82, 83, 84]) {
      cache.decode(full(id), occasionId: 71, blueprintId: id);
    }
    expect(cache.lookup(71, 81), isNull);
    final reply = cache.decode(
      thin(81),
      occasionId: 71,
      blueprintId: 81,
      known: known,
    );
    expect(reply.plan, same(known));
    expect(cache.lookup(71, 82), isNull);
    expect(
      [81, 82, 83, 84].where((id) => cache.lookup(71, id) != null),
      hasLength(3),
    );
  });

  test('a geometry save between detail and preview refreshes metadata once and reuses the new drawing', () async {
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: OccasionModel(
        id: 71,
        isHidden: false,
        isOpen: true,
        isPromoted: false,
      ),
    );
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    var details = 0, maps = 0;
    final controller = OrderDetailController(
      orderId: 4,
      occasionId: 71,
      read: (name, args) async {
        if (name == 'get_order_admin_detail') {
          details++;
          return {
            'code': 200,
            'data': {
              'order': {
                'id': 4,
                'occasion': 71,
                'state': 'ordered',
                'data': {},
              },
              'placementFingerprint': 'current',
              'plans': [
                {'id': 81, 'layoutRevision': details == 1 ? 3 : 4},
              ],
            },
          };
        }
        maps++;
        if (maps == 1) return {'code': 200, 'data': full(81, revision: 4)};
        expect(args['p_known_layout_revision'], 4);
        return {'code': 200, 'data': thin(81, revision: 4)};
      },
    );
    addTearDown(controller.dispose);
    expect(await controller.load(), isTrue);
    final view = await controller.blueprint(81);
    expect(view.plan.revision, 4);
    expect(details, 2);
    expect(maps, 2);
    expect(controller.detail!.plans.single['layoutRevision'], 4);
  });

  test(
    'a disposed order cannot populate shared drawing data from a late response',
    () async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
          id: 71,
          isHidden: false,
          isOpen: true,
          isPromoted: false,
        ),
      );
      addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = previous,
      );
      final cache = OrderBlueprintCache();
      final pending = Completer<dynamic>();
      final old = OrderDetailController(
        orderId: 4,
        occasionId: 71,
        blueprints: cache,
        read: (name, args) async {
          if (name == 'get_order_admin_detail')
            return {
              'code': 200,
              'data': {
                'order': {
                  'id': 4,
                  'occasion': 71,
                  'state': 'ordered',
                  'data': {},
                },
                'placementFingerprint': 'current',
              },
            };
          return pending.future;
        },
      );
      expect(await old.load(), isTrue);
      final request = old.blueprint(81);
      final rejected = expectLater(request, throwsStateError);
      old.dispose();
      pending.complete({'code': 200, 'data': full(81)});
      await rejected;
      expect(cache.lookup(71, 81), isNull);
    },
  );
}
