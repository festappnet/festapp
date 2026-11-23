import 'dart:convert';

import 'package:collection/collection.dart';

/// The edit intent from one server snapshot. Structural form edits still carry
/// the original catalog versions and are written together by the save RPC.
class FormSavePatch {
  FormSavePatch(
    this._baseline,
    Map<String, dynamic> edited, {
    required bool replacePaymentSelection,
  }) {
    final draft = snapshot(edited);
    for (final key in _formValues) {
      if (draft.containsKey(key) && !_same.equals(_baseline[key], draft[key])) {
        _changes[key] = draft[key];
      }
    }
    if (_hasStructuralChanges(_baseline, draft)) {
      for (final key in _structure) {
        _changes[key] = draft[key];
      }
    }
    if (draft.containsKey('customer_self_service')) {
      _changes['customer_self_service'] = draft['customer_self_service'];
    }

    final previousSettings = _baseline['settings'] as Map;
    final settings = draft['settings'] as Map;
    for (final entry in settings.entries) {
      final key = entry.key as String;
      final previous = previousSettings[key];
      final next = entry.value;
      if (_independentSettings.contains(key)) {
        final before = previous as Map? ?? const {};
        final after = next as Map? ?? const {};
        final changes = {
          for (final name in {...before.keys, ...after.keys})
            if (!_same.equals(before[name], after[name])) name: after[name],
        };
        if (changes.isNotEmpty) _settings[key] = changes;
      } else if (!_same.equals(previous, next)) {
        _settings[key] = next;
      }
    }
    if (replacePaymentSelection) {
      _changes['payment_selection_intent'] = 'replace';
    }
  }

  final Map<String, dynamic> _baseline;
  final _changes = <String, dynamic>{};
  final _settings = <String, dynamic>{};

  static const _same = DeepCollectionEquality();
  static const _formValues = [
    'participant_capacity',
    'waitlist_enabled',
    'show_remaining_capacity',
    'waitlist_offer_duration_seconds',
    'title',
    'blueprint',
    'bank_account',
    'deadline_duration_seconds',
    'is_open',
    'header',
    'header_off',
    'link',
  ];
  static const _structure = [
    'form_fields',
    'deleted_field_ids',
    'deleted_product_ids',
  ];
  static const _independentSettings = {'design', 'schedule'};

  static Map<String, dynamic> snapshot(Map<String, dynamic> values) =>
      (jsonDecode(jsonEncode(values)) as Map).cast<String, dynamic>();

  static bool _hasStructuralChanges(Map baseline, Map draft) =>
      _structure.any((key) => !_same.equals(baseline[key], draft[key]));

  static bool structureChanged(
    Map<String, dynamic> baseline,
    Map<String, dynamic> draft,
  ) => _hasStructuralChanges(baseline, snapshot(draft));

  String? get originalLink => _baseline['link'] as String?;

  Map<String, dynamic> request(int version) => {
    'id': _baseline['id'],
    'occasion': _baseline['occasion'],
    'expected_aggregate_version': version,
    'expected_product_versions': _baseline['expected_product_versions'],
    'expected_product_type_versions':
        _baseline['expected_product_type_versions'],
    ..._changes,
    if (_settings.isNotEmpty) 'settings': _settings,
  };

  bool canApplyTo(Map<String, dynamic> current) {
    if (current['id'] != _baseline['id'] ||
        current['occasion'] != _baseline['occasion'] ||
        _changes.containsKey('customer_self_service')) {
      return false;
    }
    final previousSettings = _baseline['settings'] as Map;
    final currentSettings = current['settings'] as Map;
    // Payment selection and its deadline/recipient are one intent. A change
    // to any of them needs the original configuration to still be current.
    const paymentValues = ['bank_account', 'deadline_duration_seconds'];
    const paymentSettings = ['payments', 'payment_deadline'];
    if ((_changes.containsKey('payment_selection_intent') ||
            paymentValues.any(_changes.containsKey) ||
            paymentSettings.any(_settings.containsKey)) &&
        (paymentValues.any(
              (key) => !_same.equals(_baseline[key], current[key]),
            ) ||
            paymentSettings.any(
              (key) =>
                  !_same.equals(previousSettings[key], currentSettings[key]),
            ))) {
      return false;
    }
    for (final key in _changes.keys) {
      if (!_same.equals(_baseline[key], current[key])) return false;
    }
    for (final key in _settings.keys) {
      if (_independentSettings.contains(key)) {
        final before = previousSettings[key] as Map?;
        final after = currentSettings[key] as Map?;
        if ((_settings[key] as Map).keys.any(
          (name) => !_same.equals(before?[name], after?[name]),
        )) {
          return false;
        }
      } else if (!_same.equals(previousSettings[key], currentSettings[key])) {
        return false;
      }
    }
    return true;
  }
}
