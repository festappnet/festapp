import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import '../form_feature.dart';

const int _secondsInADay = 86400;
const int _secondsInAWeek = _secondsInADay * 7;

extension FormFeatureSettingsEditor on FormFeature {
  Widget buildSettingsEditor(BuildContext context) {
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
                padding: const EdgeInsets.all(16),
                child: Text(FormStrings.occasionPaymentDefaultsHelp),
              ),
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
