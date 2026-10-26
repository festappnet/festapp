import 'blueprint_setup_layout_draft.dart';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/components/eshop/views/product_price_waves_dialog.dart';
import 'package:fstapp/components/eshop/views/product_price_wave_actions.dart';
import 'occasion_form_draft.dart';
import 'occasion_setup_details_strings.dart';

/// Serializes plans only. Actual scheduling is performed by the existing SQL
/// price-wave commands after finalization has mapped draft product IDs.
class OccasionSetupPriceWaveDraft implements ProductPriceWaveActions {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  OccasionSetupPriceWaveDraft(this.data, this.onChanged);

  List<Map<String, dynamic>> get waves =>
      (jsonDecode(jsonEncode(data['priceWaves'] ?? [])) as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
  void _save(List<Map<String, dynamic>> value) =>
      onChanged({'priceWaves': value});
  void _future(DateTime time) {
    if (!time.isAfter(DateTime.now())) throw StateError('FUTURE_TIME_REQUIRED');
  }

  @override
  Future<ProductPriceWave> create(DateTime time) async {
    _future(time);
    final list = waves;
    final existing = list
        .where((v) => DateTime.parse(v['change_time']).isAtSameMomentAs(time))
        .firstOrNull;
    if (existing != null)
      return ProductPriceWave(id: existing['id'], time: time);
    final id =
        list.fold<int>(0, (m, w) => (w['id'] as int) < m ? w['id'] as int : m) -
            1;
    list.add({
      'id': id,
      'change_time': time.toUtc().toIso8601String(),
      'targets': <Map<String, dynamic>>[]
    });
    _save(list);
    return ProductPriceWave(id: id, time: time.toUtc());
  }

  @override
  Future<void> move(ProductPriceWave wave, DateTime time) async {
    _future(time);
    final list = waves;
    if (list.any((v) =>
        v['id'] != wave.id &&
        DateTime.parse(v['change_time']).isAtSameMomentAs(time))) {
      throw StateError('PRICE_CHANGE_CONFLICT');
    }
    list.firstWhere((v) => v['id'] == wave.id)['change_time'] =
        time.toUtc().toIso8601String();
    _save(list);
  }

  @override
  Future<void> cancel(ProductPriceWave wave) async =>
      _save(waves..removeWhere((v) => v['id'] == wave.id));
  @override
  Future<void> saveTarget(ProductPriceWave wave, ProductModel product,
      double? price, bool? hidden) async {
    _future(wave.time);
    if (price != null && (!price.isFinite || price < 0))
      throw StateError('INVALID_PRICE');
    if (hidden != null && product.isUsedInBlueprint == true)
      throw StateError('BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED');
    final list = waves;
    var targetWaveId = wave.id;
    if (targetWaveId == null) {
      final existing = list
          .where((w) =>
              DateTime.parse(w['change_time']).isAtSameMomentAs(wave.time))
          .firstOrNull;
      targetWaveId = existing?['id'] ??
          list.fold<int>(
                  0, (m, w) => (w['id'] as int) < m ? w['id'] as int : m) -
              1;
      if (existing == null)
        list.add({
          'id': targetWaveId,
          'change_time': wave.time.toUtc().toIso8601String(),
          'targets': <Map<String, dynamic>>[]
        });
    }
    final targets = List<Map<String, dynamic>>.from(
        (list.firstWhere((v) => v['id'] == targetWaveId)['targets'] as List)
            .map((v) => Map<String, dynamic>.from(v)));
    targets.removeWhere((t) => t['product'] == product.id);
    if (price != null || hidden != null)
      targets.add({'product': product.id, 'price': price, 'is_hidden': hidden});
    list.firstWhere((v) => v['id'] == targetWaveId)['targets'] = targets;
    _save(list);
  }

  ProductsEditBundle bundle() {
    final form =
        draftFormBundle(Map<String, dynamic>.from(data['formDraft'] as Map));
    final plans = waves;
    var id = 0;
    return ProductsEditBundle(
      products: [
        for (final product in form.products)
          product.copyWith(
            isUsedInBlueprint: SetupBlueprintConfiguration(data).active &&
                (data['blueprintObjects'] as List? ?? [])
                    .whereType<Map>()
                    .any((o) => o['product'] == product.id),
            priceChanges: [
              for (final wave in plans)
                for (final target in wave['targets'] as List)
                  if (target['product'] == product.id &&
                      target['price'] != null)
                    ProductPriceChange(
                        id: --id,
                        revision: 1,
                        waveId: wave['id'],
                        price: (target['price'] as num).toDouble(),
                        time: DateTime.parse(wave['change_time']).toUtc())
            ],
            visibilityChanges: [
              for (final wave in plans)
                for (final target in wave['targets'] as List)
                  if (target['product'] == product.id &&
                      target['is_hidden'] != null)
                    ProductVisibilityChange(
                        id: --id,
                        revision: 1,
                        waveId: wave['id'],
                        hidden: target['is_hidden'],
                        time: DateTime.parse(wave['change_time']).toUtc())
            ],
          )
      ],
      priceWaves: [
        for (final wave in plans)
          ProductPriceWave(
              id: wave['id'], time: DateTime.parse(wave['change_time']).toUtc())
      ],
      productTypes: form.productTypes,
      inventoryPools: const [],
      inventoryContexts: const [],
      forms: const [],
    );
  }
}

class OccasionSetupPricing extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const OccasionSetupPricing(
      {super.key, required this.data, required this.onChanged});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(OccasionSetupDetailsStrings.text('enablePriceWaves')),
          subtitle: Text(OccasionSetupDetailsStrings.text('priceWavesHint')),
          value: data['priceWavesEnabled'] == true,
          onChanged: (v) => onChanged({'priceWavesEnabled': v}),
        ),
        if (data['priceWavesEnabled'] == true) ...[
          const SizedBox(height: 16),
          Text(
              '${(data['priceWaves'] as List? ?? []).length} ${OccasionSetupDetailsStrings.text('priceWaveCount')}'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.timeline),
            label: Text(OccasionSetupDetailsStrings.text('editPriceWaves')),
            onPressed: () {
              final draft = OccasionSetupPriceWaveDraft(data, onChanged);
              showDialog<void>(
                  context: context,
                  builder: (_) => ProductPriceWavesDialog(
                        occasionLink: '',
                        occasionEnd:
                            DateTime.tryParse(data['end'] as String? ?? ''),
                        initialBundle: draft.bundle(),
                        canEdit: true,
                        actions: draft,
                        loader: () async => draft.bundle(),
                      ));
            },
          ),
        ],
      ]);
}
