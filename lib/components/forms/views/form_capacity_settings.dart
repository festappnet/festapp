import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/standard_dialog.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import '../../features/feature_service.dart';
import '../../features/feature_constants.dart';
import '../waitlist_strings.dart';

/// Edits the existing form draft. The editor's Save/Discard owns persistence.
class FormCapacitySettings extends StatelessWidget {
  const FormCapacitySettings(
      {super.key,
      required this.form,
      required this.canEdit,
      required this.onChanged});
  final FormEditorDraft form;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final blueprint = form.definition.blueprint != null &&
        FeatureService.isFeatureEnabled(FeatureConstants.blueprint);
    final snapshot = form.definition.capacity;
    final occupancy = !blueprint && snapshot?.limit != null
        ? WaitlistStrings.text('occupancy')
            .replaceAll('{occupied}', '${snapshot!.occupiedPlaces}')
            .replaceAll('{capacity}', '${snapshot.limit}')
        : null;
    final settingsSummary = blueprint
        ? WaitlistStrings.blueprintCapacity
        : form.definition.participantCapacity == null
            ? WaitlistStrings.unlimited
            : '${occupancy ?? '${WaitlistStrings.capacity}: ${form.definition.participantCapacity}'}\n'
                '${(form.definition.waitlistEnabled ? WaitlistStrings.waitlistOn : WaitlistStrings.waitlistOff)}';
    final showOffers = !blueprint &&
        form.definition.participantCapacity != null &&
        form.definition.waitlistEnabled &&
        (form.definition.capacity?.offeredPlaces ?? 0) > 0;
    final counts = form.definition.capacity == null
        ? null
        : [
            if (occupancy == null)
              '${OrderItemStrings.validTickets}: ${form.definition.capacity!.occupiedPeople}',
            if (showOffers)
              '${WaitlistStrings.offeredPlacesCount}: ${form.definition.capacity!.offeredPlaces}',
          ].join('\n');
    final summary = [settingsSummary, if (counts != null) counts].join('\n');
    return ListTile(
      enabled: !blueprint,
      contentPadding: EdgeInsets.zero,
      title: Text(WaitlistStrings.settings,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle:
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(summary)),
      trailing: canEdit && !blueprint ? const Icon(Icons.chevron_right) : null,
      onTap: canEdit && !blueprint
          ? () async {
              final changed = await showDialog<bool>(
                  context: context,
                  builder: (_) => FormCapacityDialog(form: form));
              if (changed == true) onChanged();
            }
          : null,
    );
  }
}

class FormCapacityDialog extends StatefulWidget {
  const FormCapacityDialog({super.key, required this.form});
  final FormEditorDraft form;
  @override
  State<FormCapacityDialog> createState() => _FormCapacityDialogState();
}

class _FormCapacityDialogState extends State<FormCapacityDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _capacity;
  late final TextEditingController _hours;
  late bool _limited;
  late bool _waitlist;
  late bool _showRemaining;
  bool get _blocked =>
      (widget.form.definition.capacity?.waitingPeople ?? 0) > 0 ||
      (widget.form.definition.capacity?.offeredPlaces ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _limited = widget.form.definition.participantCapacity != null;
    _waitlist = widget.form.definition.waitlistEnabled;
    _showRemaining = widget.form.definition.showRemainingCapacity;
    _capacity = TextEditingController(
        text: widget.form.definition.participantCapacity?.toString() ?? '');
    final hours =
        (widget.form.definition.waitlistOfferDurationSeconds ?? 86400) / 3600;
    _hours = TextEditingController(
        text: hours == hours.roundToDouble()
            ? hours.toInt().toString()
            : hours.toString());
  }

  @override
  void dispose() {
    _capacity.dispose();
    _hours.dispose();
    super.dispose();
  }

  double? get _duration => double.tryParse(_hours.text.replaceAll(',', '.'));

  void _apply() {
    if (!_key.currentState!.validate()) return;
    widget.form.definition = widget.form.definition.copyWith(
      participantCapacity: _limited ? int.tryParse(_capacity.text) : null,
      waitlistEnabled: _limited && _waitlist,
      showRemainingCapacity: _showRemaining,
      waitlistOfferDurationSeconds:
          _limited && _waitlist ? (_duration! * 3600).round() : null,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => StandardDialog(
        maxWidth: 560,
        title: Text(WaitlistStrings.settings),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                  child: SingleChildScrollView(
                      child: Form(
                          key: _key,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(FeatureService.isFeatureEnabled(
                                            FeatureConstants.ticket)
                                        ? WaitlistStrings.limitTickets
                                        : WaitlistStrings.limitCapacity),
                                    subtitle: Text(_blocked
                                        ? WaitlistStrings.activeEntries
                                        : _limited
                                            ? WaitlistStrings
                                                .capacityHelpLimited
                                            : WaitlistStrings.capacityHelp),
                                    value: _limited,
                                    onChanged: _blocked
                                        ? null
                                        : (value) =>
                                            setState(() => _limited = value)),
                                if (_limited) ...[
                                  const SizedBox(height: 16),
                                  if (widget.form.definition.capacity !=
                                      null) ...[
                                    Text(
                                        '${OrderItemStrings.validTickets}: ${widget.form.definition.capacity!.occupiedPeople}'),
                                    if (widget.form.definition.capacity!
                                            .offeredPlaces >
                                        0)
                                      Text(
                                          '${WaitlistStrings.offeredPlacesCount}: ${widget.form.definition.capacity!.offeredPlaces}'),
                                    const SizedBox(height: 12),
                                  ],
                                  TextFormField(
                                      controller: _capacity,
                                      decoration: InputDecoration(
                                          labelText:
                                              FeatureService.isFeatureEnabled(
                                                      FeatureConstants.ticket)
                                                  ? WaitlistStrings.text(
                                                      'capacityTickets')
                                                  : WaitlistStrings.text(
                                                      'capacityRegistrations'),
                                          border: const OutlineInputBorder(),
                                          errorMaxLines: 4),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      validator: (value) {
                                        final number =
                                            int.tryParse(value ?? '');
                                        if (number == null || number <= 0) {
                                          return WaitlistStrings.positiveNumber;
                                        }
                                        if (number <
                                            (widget.form.definition.capacity
                                                    ?.minimumCapacity ??
                                                0)) {
                                          return WaitlistStrings.text(
                                              'CAPACITY_BELOW_COMMITTED');
                                        }
                                        return null;
                                      }),
                                  const SizedBox(height: 8),
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title:
                                          Text(WaitlistStrings.showRemaining),
                                      value: _showRemaining,
                                      onChanged: (value) => setState(
                                          () => _showRemaining = value)),
                                  const Divider(height: 24),
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(WaitlistStrings.enabled),
                                      subtitle:
                                          Text(WaitlistStrings.waitlistHelp),
                                      value: _waitlist,
                                      onChanged: _blocked
                                          ? null
                                          : (value) => setState(
                                              () => _waitlist = value)),
                                  if (_waitlist) ...[
                                    const SizedBox(height: 16),
                                    TextFormField(
                                        controller: _hours,
                                        decoration: InputDecoration(
                                            labelText:
                                                WaitlistStrings.durationHours,
                                            helperText:
                                                WaitlistStrings.durationHelp,
                                            helperMaxLines: 4,
                                            errorMaxLines: 3,
                                            border: const OutlineInputBorder()),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        validator: (_) => _duration != null &&
                                                _duration!.isFinite &&
                                                (_duration! * 3600).round() > 0
                                            ? null
                                            : WaitlistStrings.positiveNumber),
                                  ],
                                ],
                                const SizedBox(height: 16),
                                Text(WaitlistStrings.saveWithForm,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ])))),
              const SizedBox(height: 16),
              OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(CommonStrings.storno)),
                    FilledButton(
                        onPressed: _apply,
                        child: Text(WaitlistStrings.applySettings)),
                  ]),
            ]),
      );
}
