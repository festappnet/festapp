import 'package:material_ui/material_ui.dart';

import '../features/feature.dart';

class OccasionFeatureErrors {
  final String code;
  final Set<FormFieldState<dynamic>> fields;
  OccasionFeatureErrors(this.code, this.fields);
}

/// Local public FormState registry. It owns no domain data or persistence.
class OccasionFeaturesController {
  final Map<String, (Feature, GlobalKey<FormState>)> _forms = {};
  void Function(String)? onReveal;
  void register(Feature feature, GlobalKey<FormState> key) {
    _forms[feature.code] = (feature, key);
  }

  void unregister(String code, GlobalKey<FormState> key) {
    if (identical(_forms[code]?.$2, key)) _forms.remove(code);
  }

  void save() {
    for (final entry in _forms.values) {
      entry.$2.currentState?.save();
    }
  }

  void saveFeature(String code) => _forms[code]?.$2.currentState?.save();
  List<OccasionFeatureErrors> validateGranularly() {
    final errors = <OccasionFeatureErrors>[];
    for (final entry in _forms.entries) {
      if (!entry.value.$1.isEnabled) continue;
      final invalid = entry.value.$2.currentState?.validateGranularly();
      if (invalid != null && invalid.isNotEmpty) {
        errors.add(OccasionFeatureErrors(entry.key, invalid));
      }
    }
    return errors;
  }

  void reveal(String code) => onReveal?.call(code);
}
