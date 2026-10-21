import 'dart:convert';
import 'occasion_setup_story.dart';

/// References belong to the selected form, even when layout geometry comes
/// from another occasion. Only explicit choices may reassign their meaning.
class OccasionSetupReferences {
  OccasionSetupReferences(this.data);
  final Map<String, dynamic> data;

  Map<int, Map> get types {
    final result = <int, Map>{};
    for (final field in ((data['formDraft'] as Map?)?['fields'] as List? ?? []).whereType<Map>()) {
      final type = field['product_type_data'] ?? field['product_type'];
      if (type is Map && type['id'] is num) result[(type['id'] as num).toInt()] = type;
    }
    return result;
  }
  Map<int, Map> get seatProducts => {
        for (final type in types.values.where((type) => type['type'] == 'spot'))
          for (final product
              in (type['products'] as List? ?? []).whereType<Map>())
            if (product['id'] is num) (product['id'] as num).toInt(): product,
      };
  bool get blueprintActive =>
      OccasionSetupStory.formEnabled(data) &&
      data['blueprintMode'] != 'Bez plánku';
  Iterable<Map> get _blueprintBindings sync* {
    if (!blueprintActive) return;
    final draft = data['blueprintLayoutDraft'];
    if (draft is! Map) return;
    for (final key in ['seatBindings', 'groupProducts', 'areaBindings']) {
      yield* (draft[key] as List? ?? []).whereType<Map>();
    }
  }

  Iterable<Map> get _templates sync* {
    if (!OccasionSetupStory.hasTickets(data)) return;
    final templates = (data['ticketDraft'] as Map?)?['layout']?['templates'];
    if (templates is Map) yield* templates.values.whereType<Map>();
  }

  Set<int> get missingProducts => {
        for (final binding in _blueprintBindings)
          if (binding['productId'] is num &&
              !seatProducts.containsKey((binding['productId'] as num).toInt()))
            (binding['productId'] as num).toInt(),
      };
  Set<int> get missingTypes => {
        for (final template in _templates)
          for (final element
              in (template['elements'] as List? ?? []).whereType<Map>())
            if (element['binding'] == 'productType' &&
                element['productTypeId'] is num &&
                !types.containsKey((element['productTypeId'] as num).toInt()))
              (element['productTypeId'] as num).toInt(),
      };
  bool get duplicateTypes => _templates.any((template) {
        final ids = (template['elements'] as List? ?? [])
            .whereType<Map>()
            .where((e) => e['binding'] == 'productType')
            .map((e) => e['productTypeId'])
            .toList();
        return ids.toSet().length != ids.length;
      });
  bool get hasIssues =>
      missingProducts.isNotEmpty || missingTypes.isNotEmpty || duplicateTypes;

  Map<String, dynamic> rebind(
      {required Map<int, int> products, required Map<int, int> productTypes}) {
    final next = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
    final blueprint = next['blueprintLayoutDraft'];
    if (blueprintActive && blueprint is Map) {
      for (final key in ['seatBindings', 'groupProducts', 'areaBindings']) {
        for (final binding
            in (blueprint[key] as List? ?? []).whereType<Map>()) {
          final replacement = products[binding['productId']];
          if (replacement != null) binding['productId'] = replacement;
        }
      }
    }
    if (OccasionSetupStory.hasTickets(next)) {
      final templates = (next['ticketDraft'] as Map?)?['layout']?['templates'];
      if (templates is Map) {
        for (final template in templates.values.whereType<Map>()) {
          for (final element
              in (template['elements'] as List? ?? []).whereType<Map>()) {
            if (element['binding'] != 'productType') continue;
            final replacement = productTypes[element['productTypeId']];
            if (replacement != null) element['productTypeId'] = replacement;
          }
        }
      }
    }
    return next;
  }
}
