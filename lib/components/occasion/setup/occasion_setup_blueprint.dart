import 'dart:convert';

import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'occasion_form_draft.dart';
import 'occasion_setup_strings.dart';

enum SetupBlueprintMode { none, create, copy }

/// Owns the active draft plan. Only authoring data crosses this boundary.
class OccasionSetupBlueprint {
  final Map<String, dynamic> draft;
  OccasionSetupBlueprint(this.draft);

  SetupBlueprintMode get mode => switch (draft['blueprintMode']) {
        'new' || 'Nový' => SetupBlueprintMode.create,
        'copy' || 'Převzít' => SetupBlueprintMode.copy,
        null => (draft['blueprintObjects'] as List? ?? []).isEmpty
            ? SetupBlueprintMode.none
            : SetupBlueprintMode.copy,
        _ => SetupBlueprintMode.none,
      };
  String get modeId => switch (mode) {
        SetupBlueprintMode.none => 'none',
        SetupBlueprintMode.create => 'new',
        SetupBlueprintMode.copy => 'copy',
      };
  String get label => OccasionSetupStrings.story('blueprint.$modeId');
  int get seatCount => (draft['blueprintObjects'] as List? ?? [])
      .where((o) => o is Map && o['type'] == 'spot')
      .length;
  bool get ready =>
      mode == SetupBlueprintMode.none ||
      (draft['formEnabled'] == true &&
          seatCount > 0 &&
          (plan().objects ?? [])
              .where((o) => o.type == 'spot')
              .every((o) => o.product?.productTypeString == 'spot'));

  void clear({bool create = false}) {
    draft.addAll({
      'blueprintMode': create ? 'new' : 'none',
      'blueprintSourceId': null,
      'blueprintObjects': <Map<String, dynamic>>[],
      'blueprintGroups': <Map<String, dynamic>>[],
      'blueprintBackground': null,
      'blueprintWidth': 12,
      'blueprintHeight': 8
    });
    normalizeForm(draft);
  }

  void importPlan(Map source) {
    // Parse the complete copy before touching the last valid draft.
    final input = Map<String, dynamic>.from(jsonDecode(jsonEncode(source)));
    final raw = input['objects'];
    int gridNumber(dynamic value) {
      if (value is num && value.isFinite && value == value.roundToDouble()) {
        return value.toInt();
      }
      throw const FormatException(
          'Plánek má nepodporované souřadnice nebo rozměry.');
    }

    final dimensions = (input['configuration'] as Map?)?['dimensions'];
    if (dimensions is Map) {
      dimensions['width'] = gridNumber(dimensions['width']);
      dimensions['height'] = gridNumber(dimensions['height']);
    }
    if (raw is List) {
      for (final object in raw.whereType<Map>()) {
        object['x'] = gridNumber(object['x']);
        object['y'] = gridNumber(object['y']);
      }
    }
    if (raw is! List ||
        raw.any((o) =>
            o is! Map ||
            !['spot', 'table'].contains(o['type']) ||
            o['x'] is! int ||
            o['y'] is! int)) {
      throw const FormatException(
          'Nepodporovaný formát plánku. Vyberte jiný nebo vytvořte nový.');
    }
    for (var i = 0; i < raw.length; i++) {
      raw[i]['id'] ??= -(i + 1);
    }
    input['spots'] ??= raw.where((o) => o['type'] == 'spot').toList();
    for (final group in input['groups'] as List? ?? []) {
      for (final object in raw) {
        if ((group['items'] as List? ?? []).contains(object['id'])) {
          object['group'] ??= group['id'];
        }
      }
    }
    final parsed = BlueprintModel.fromJson(input);
    if ((parsed.configuration?.width ?? 0) <= 0 ||
        (parsed.configuration?.height ?? 0) <= 0) {
      throw const FormatException('Plánek nemá platné rozměry.');
    }
    for (var i = 0; i < raw.length; i++) {
      final object = parsed.objects![i];
      object.groupId = raw[i]['group'];
      object.group =
          parsed.groups?.where((g) => g.id == object.groupId).firstOrNull;
    }
    writePlan(parsed);
    draft['blueprintMode'] = 'copy';
    draft['blueprintSourceId'] = source['id'];
    normalizeForm(draft);
  }

  void writePlan(BlueprintModel plan) {
    draft.addAll({
      'blueprintObjects': (plan.objects ?? [])
          .map((o) => o.toJson()
            ..remove('state')
            ..remove('id')
            ..remove('order_product_ticket'))
          .toList(),
      'blueprintGroups': (plan.groups ?? []).map((g) => g.toJson()).toList(),
      'blueprintWidth': plan.configuration?.width ?? 12,
      'blueprintHeight': plan.configuration?.height ?? 8,
      'blueprintTitle': plan.title,
      'blueprintBackground': plan.backgroundSvg,
    });
    normalizeForm(draft);
  }

  BlueprintModel plan() {
    final form = draft['formDraft'];
    final products = form is Map
        ? draftFormBundle(Map<String, dynamic>.from(form)).products
        : null;
    final objects = (draft['blueprintObjects'] as List? ?? [])
        .indexed
        .map((entry) => {
              ...Map<String, dynamic>.from(entry.$2 as Map),
              'id': -(entry.$1 + 1)
            })
        .toList();
    // Canonical read adapter expects separate spot facts even for modern inline objects.
    final result = BlueprintModel.fromJson({
      'title': draft['blueprintTitle'] ?? 'Plán sálu',
      'configuration': {
        'dimensions': {
          'width': (draft['blueprintWidth'] as num?)?.toInt() ?? 12,
          'height': (draft['blueprintHeight'] as num?)?.toInt() ?? 8
        }
      },
      'objects': objects,
      'spots': objects.where((o) => o['type'] == 'spot').toList(),
      'groups': draft['blueprintGroups'] ?? [],
      'background_svg': draft['blueprintBackground'],
      'products': products
          ?.map((p) => {...p.toJson(), 'type': p.productTypeString})
          .toList(),
    });
    // New draft seats have no database IDs; restore inline bindings by position.
    for (var i = 0; i < (result.objects?.length ?? 0); i++) {
      final o = result.objects![i];
      o.title = objects[i]['title'];
      o.spotProduct = objects[i]['product'];
      o.product = products?.where((p) => p.id == o.spotProduct).firstOrNull;
      o.orderProductTicket = null;
    }
    for (final group in result.groups ?? []) {
      group.product = group.objects.map((o) => o.product).nonNulls.firstOrNull;
    }
    result.assignAllSpotsWithBlueprint();
    return result;
  }

  static void normalizeForm(Map<String, dynamic> draft) {
    final owner = OccasionSetupBlueprint(draft);
    draft['blueprintMode'] = owner.modeId;
    final form = draft['formDraft'];
    if (form is! Map) return;
    final fields = List<dynamic>.from(form['fields'] as List? ?? []);
    fields.removeWhere((f) => f is Map && f['type'] == 'spot');
    if (owner.mode != SetupBlueprintMode.none &&
        (draft['eventKind'] == null || draft['eventKind'] == 'ball')) {
      fields.add({
        'type': 'spot',
        'is_ticket_field': true,
        'is_hidden': false,
        'order': -1
      });
    }
    form['fields'] = fields;
    form['blueprint'] = null;
    draft.remove('seatSelection');
  }
}
