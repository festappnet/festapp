import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'feature.dart';
import 'feature_constants.dart';
import 'features_strings.dart';

/// Feature for importing users from different sources.
class ImportFeature extends Feature {
  static const String metaImportFromCsv = "import_from_csv";
  static const String metaImportFromTickets = "import_from_tickets";

  bool importFromCsv;
  bool importFromTickets;
  bool autoImport;

  ImportFeature({
    super.code = FeatureConstants.import,
    super.isEnabled = true, // Enabled by default
    super.title,
    super.description,
    this.importFromCsv = false,
    this.importFromTickets = false,
    this.autoImport = false,
  });

  /// Creates an ImportFeature from a JSON object.
  factory ImportFeature.fromJson(Map<String, dynamic> json) {
    return ImportFeature(
      code: json[FeatureConstants.metaCode] ?? FeatureConstants.import,
      isEnabled:
          json[FeatureConstants.metaIsEnabled] ?? true, // Enabled by default
      title: json[FeatureConstants.metaTitle],
      description: json[FeatureConstants.metaDescription],
      importFromCsv: json[metaImportFromCsv] ?? false,
      importFromTickets: json[metaImportFromTickets] ?? false,
      autoImport: json[FeatureConstants.importAutoImport] ?? false,
    );
  }

  /// Converts the feature to a JSON object.
  @override
  Map<String, dynamic> toJson() {
    return {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      metaImportFromCsv: importFromCsv,
      metaImportFromTickets: importFromTickets,
      FeatureConstants.importAutoImport: autoImport,
    };
  }

  /// Builds the form field widget for this feature.
  @override
  Widget buildFormField(BuildContext context) {
    return _ImportFeatureForm(feature: this);
  }
}

/// A stateful widget to manage the form's UI state for the ImportFeature.
class _ImportFeatureForm extends StatefulWidget {
  final ImportFeature feature;

  const _ImportFeatureForm({required this.feature});

  @override
  State<_ImportFeatureForm> createState() => _ImportFeatureFormState();
}

class _ImportFeatureFormState extends State<_ImportFeatureForm> {
  void _refresh(VoidCallback change) {
    setState(change);
    EditorDraftScope.changed(context);
  }

  late bool _importFromCsv;
  late bool _importFromTickets;
  late bool _autoImport;

  @override
  void initState() {
    super.initState();
    _importFromCsv = widget.feature.importFromCsv;
    _importFromTickets = widget.feature.importFromTickets;
    _autoImport = widget.feature.autoImport;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(FeaturesStrings.labelImportFromCsv),
          value: _importFromCsv,
          onChanged: (bool value) {
            _refresh(() {
              _importFromCsv = value;
              widget.feature.importFromCsv = value;
            });
          },
        ),
        SwitchListTile(
          title: Text(FeaturesStrings.labelImportFromTickets),
          value: _importFromTickets,
          onChanged: (bool value) {
            _refresh(() {
              _importFromTickets = value;
              widget.feature.importFromTickets = value;

              // If Import from Tickets is disabled, Auto Import must also be disabled.
              if (!value) {
                _autoImport = false;
                widget.feature.autoImport = false;
              }
            });
          },
        ),
        if (AppConfig.isAppSupported)
          Column(
            children: [
              const Divider(),
              SwitchListTile(
                title: Text(FeaturesStrings.labelAutoImport),
                subtitle: Text(FeaturesStrings.helperAutoImport),
                value: _autoImport,
                // If _importFromTickets is false, we set onChanged to null.
                // This creates a disabled (greyed out) UI state.
                onChanged: _importFromTickets
                    ? (bool value) {
                        _refresh(() {
                          _autoImport = value;
                          widget.feature.autoImport = value;
                        });
                      }
                    : null,
              ),
            ],
          ),
      ],
    );
  }
}
