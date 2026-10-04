import 'package:fstapp/components/_shared/editor_draft_scope.dart';
// form_feature.dart
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart'; // Import AppConfig
import '../forms/form_strings.dart';
import 'feature.dart';
import 'feature_constants.dart';

const int _secondsInADay = 86400;
const int _secondsInAWeek = _secondsInADay * 7;

/// Feature for external form & custom button title.
class FormFeature extends Feature {
  bool? formUseExternal;
  String? formExternalLink;
  String? formExternalPrice;
  String? reserveButtonTitle;
  bool? reminderIsEnabled;
  int? reminderIntervalSeconds;
  int? deadlineDurationSeconds;

  FormFeature({
    required super.code,
    bool? isEnabled, // Make this a normal parameter, not 'super.isEnabled'
    super.title,
    super.description,
    this.formUseExternal,
    this.formExternalLink,
    this.formExternalPrice,
    this.reserveButtonTitle,
    this.reminderIsEnabled,
    this.deadlineDurationSeconds,
    this.reminderIntervalSeconds,
  }) : super(
          // Pass the processed value to the super constructor.
          // This is the new centralized logic.
          isEnabled: (!AppConfig.isAppSupported) ? true : (isEnabled ?? false),
        );

  /// This feature can only be disabled if the app is supported.
  @override
  bool get canBeDisabled => AppConfig.isAppSupported;

  factory FormFeature.fromJson(Map<String, dynamic> json) {
    // This factory is now simpler. It just passes the JSON value
    // to the main constructor, which will handle the logic.
    return FormFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled:
          json[FeatureConstants.metaIsEnabled], // Let the constructor handle it
      formUseExternal: json[FeatureConstants.formUseExternal],
      formExternalLink: json[FeatureConstants.formExternalLink],
      formExternalPrice: json[FeatureConstants.formExternalPrice],
      reserveButtonTitle: json[FeatureConstants.reserveButtonTitle],
      reminderIsEnabled: json[FeatureConstants.reminderIsEnabled] ?? true,
      reminderIntervalSeconds:
          json[FeatureConstants.reminderIntervalSeconds] ?? _secondsInADay,
      deadlineDurationSeconds:
          json[FeatureConstants.deadlineDurationSeconds] ?? _secondsInAWeek,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final bool mustBeEnabled = !AppConfig.isAppSupported;

    final data = {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: mustBeEnabled ? true : isEnabled,
    };
    if (formUseExternal != null)
      data[FeatureConstants.formUseExternal] = formUseExternal!;
    if (formExternalLink != null)
      data[FeatureConstants.formExternalLink] = formExternalLink!;
    if (formExternalPrice != null)
      data[FeatureConstants.formExternalPrice] = formExternalPrice!;
    if (reserveButtonTitle != null)
      data[FeatureConstants.reserveButtonTitle] = reserveButtonTitle!;
    if (reminderIsEnabled != null)
      data[FeatureConstants.reminderIsEnabled] = reminderIsEnabled!;
    if (reminderIntervalSeconds != null)
      data[FeatureConstants.reminderIntervalSeconds] = reminderIntervalSeconds!;
    if (deadlineDurationSeconds != null)
      data[FeatureConstants.deadlineDurationSeconds] = deadlineDurationSeconds!;
    return data;
  }

  @override
  Widget buildFormField(BuildContext context) {
    return _FormFeatureEditor(formFeature: this);
  }
}

class _FormFeatureEditor extends StatefulWidget {
  final FormFeature formFeature;
  const _FormFeatureEditor({required this.formFeature});

  @override
  State<_FormFeatureEditor> createState() => _FormFeatureEditorState();
}

class _FormFeatureEditorState extends State<_FormFeatureEditor> {
  void _refresh(VoidCallback change) {
    setState(change);
    EditorDraftScope.changed(context);
  }

  late final TextEditingController _externalLinkController;
  late final TextEditingController _externalPriceController;
  late final TextEditingController _reserveButtonController;
  late final TextEditingController _deadlineController;
  late final TextEditingController _reminderController;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with values from the model.
    _externalLinkController =
        TextEditingController(text: widget.formFeature.formExternalLink);
    _externalPriceController =
        TextEditingController(text: widget.formFeature.formExternalPrice);
    _reserveButtonController =
        TextEditingController(text: widget.formFeature.reserveButtonTitle);

    // For day-based fields, convert seconds from the model to days for the UI.
    final deadlineDays = widget.formFeature.deadlineDurationSeconds;
    _deadlineController = TextEditingController(
        text: deadlineDays != null
            ? (deadlineDays / _secondsInADay).round().toString()
            : "");

    final reminderDays = widget.formFeature.reminderIntervalSeconds;
    _reminderController = TextEditingController(
        text: reminderDays != null
            ? (reminderDays / _secondsInADay).round().toString()
            : "");
  }

  @override
  void dispose() {
    // Dispose all controllers to prevent memory leaks.
    _externalLinkController.dispose();
    _externalPriceController.dispose();
    _reserveButtonController.dispose();
    _deadlineController.dispose();
    _reminderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        SwitchListTile(
          title: Text(FormStrings.labelUseExternalForm),
          value: widget.formFeature.formUseExternal ?? false,
          onChanged: (v) {
            _refresh(() {
              widget.formFeature.formUseExternal = v;
              // When toggling, clear the fields of the other mode to prevent confusion.
              if (v) {
                // Switched to external: clear internal fields' controllers
                _deadlineController.clear();
                _reminderController.clear();
              } else {
                // Switched to internal: clear external fields' controllers
                _externalLinkController.clear();
                _externalPriceController.clear();
              }
            });
          },
        ),
        if (widget.formFeature.formUseExternal ?? false)
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextFormField(
                  controller: _externalLinkController,
                  decoration: InputDecoration(
                    labelText: FormStrings.labelReservationLink,
                    helperText: FormStrings.helperReservationLink,
                  ),
                  onSaved: (val) => widget.formFeature.formExternalLink = val,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextFormField(
                  controller: _externalPriceController,
                  decoration: InputDecoration(
                    labelText: FormStrings.labelPrice,
                    helperText: FormStrings.helperPrice,
                  ),
                  onSaved: (val) => widget.formFeature.formExternalPrice = val,
                ),
              ),
            ],
          ),
        if (!(widget.formFeature.formUseExternal ?? false))
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextFormField(
                  controller: _deadlineController,
                  decoration: InputDecoration(
                    labelText: FormStrings.labelDeadlineDuration,
                    helperText: FormStrings.helperDeadlineDuration,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) =>
                      _refresh(() {}), // Rebuild for live validation
                  onSaved: (val) {
                    final days = int.tryParse(val ?? '');
                    widget.formFeature.deadlineDurationSeconds =
                        days != null ? days * _secondsInADay : _secondsInAWeek;
                  },
                ),
              ),
              SwitchListTile(
                title: Text(FormStrings.labelReminderEnabled),
                subtitle: Text(FormStrings.helperReminderEnabled),
                value: widget.formFeature.reminderIsEnabled ?? true,
                onChanged: (v) =>
                    _refresh(() => widget.formFeature.reminderIsEnabled = v),
              ),
              if (widget.formFeature.reminderIsEnabled ?? true)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: TextFormField(
                    controller: _reminderController,
                    decoration: InputDecoration(
                      labelText: FormStrings.labelReminderInterval,
                      helperText: FormStrings.helperReminderInterval,
                      errorText:
                          (int.tryParse(_reminderController.text) ?? 1) >=
                                  (int.tryParse(_deadlineController.text) ?? 7)
                              ? FormStrings.validationReminderInterval
                              : null,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) =>
                        _refresh(() {}), // Rebuild for live validation
                    onSaved: (val) {
                      final days = int.tryParse(val ?? '');
                      widget.formFeature.reminderIntervalSeconds =
                          days != null ? days * _secondsInADay : _secondsInADay;
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: Text(FormStrings.labelAdvancedSettings),
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextFormField(
                controller: _reserveButtonController,
                decoration: InputDecoration(
                    labelText: FormStrings.labelReserveButtonTitle),
                onSaved: (val) => widget.formFeature.reserveButtonTitle = val,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
