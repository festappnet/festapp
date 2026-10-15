import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/features_strings.dart';
import '../import_feature.dart';

extension ImportFeatureSettingsEditor on ImportFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return _ImportFeatureForm(feature: this);
  }
}

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
