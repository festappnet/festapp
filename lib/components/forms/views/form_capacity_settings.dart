import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/standard_dialog.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import '../models/form_model.dart';
import '../waitlist_strings.dart';

/// Edits the existing form draft. The editor's Save/Discard owns persistence.
class FormCapacitySettings extends StatelessWidget {
  const FormCapacitySettings(
      {super.key,
      required this.form,
      required this.canEdit,
      required this.onChanged});
  final FormModel form;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final blueprint = form.blueprint != null;
    final snapshot = form.capacity;
    final occupancy = !blueprint && snapshot?.limit != null
        ? WaitlistStrings.text('occupancy')
            .replaceAll('{occupied}', '${snapshot!.occupiedPeople}')
            .replaceAll('{capacity}', '${snapshot.limit}')
        : null;
    final settingsSummary = blueprint
        ? WaitlistStrings.blueprintCapacity
        : form.participantCapacity == null
            ? WaitlistStrings.unlimited
            : '${occupancy ?? '${WaitlistStrings.capacity}: ${form.participantCapacity}'}\n'
                '${(form.waitlistEnabled ? WaitlistStrings.waitlistOn : WaitlistStrings.waitlistOff)}';
    final showOffers = !blueprint &&
        form.participantCapacity != null &&
        form.waitlistEnabled &&
        (form.capacity?.offeredPlaces ?? 0) > 0;
    final counts = form.capacity == null
        ? null
        : [
            if (occupancy == null)
              '${OrdersStrings.validTickets}: ${form.capacity!.occupiedPeople}',
            if (showOffers)
              '${WaitlistStrings.offeredPlacesCount}: ${form.capacity!.offeredPlaces}',
          ].join('\n');
    final summary = [settingsSummary, if (counts != null) counts].join('\n');
    return ListTile(
      enabled: !blueprint,
      contentPadding: EdgeInsets.zero,
      title: Text(WaitlistStrings.settings,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle:
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(summary,
              semanticsLabel: occupancy == null ? null : summary.replaceFirst(
                  occupancy, '${OrdersStrings.validTickets}: ${snapshot!.occupiedPeople} / ${snapshot.limit}'))),
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
  final FormModel form;
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
      (widget.form.capacity?.waitingPeople ?? 0) > 0 ||
      (widget.form.capacity?.offeredPlaces ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _limited = widget.form.participantCapacity != null;
    _waitlist = widget.form.waitlistEnabled;
    _showRemaining = widget.form.showRemainingCapacity;
    _capacity = TextEditingController(
        text: widget.form.participantCapacity?.toString() ?? '');
    final hours = (widget.form.waitlistOfferDurationSeconds ?? 86400) / 3600;
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
    widget.form.participantCapacity =
        _limited ? int.parse(_capacity.text) : null;
    widget.form.waitlistEnabled = _limited && _waitlist;
    widget.form.showRemainingCapacity = _showRemaining;
    widget.form.waitlistOfferDurationSeconds =
        _limited && _waitlist ? (_duration! * 3600).round() : null;
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
                                    title: Text(WaitlistStrings.limitCapacity),
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
                                  if (widget.form.capacity != null) ...[
                                    Text(
                                        '${OrdersStrings.validTickets}: ${widget.form.capacity!.occupiedPeople}'),
                                    if (widget.form.capacity!.offeredPlaces > 0)
                                      Text(
                                          '${WaitlistStrings.offeredPlacesCount}: ${widget.form.capacity!.offeredPlaces}'),
                                    const SizedBox(height: 12),
                                  ],
                                  TextFormField(
                                      controller: _capacity,
                                      decoration: InputDecoration(
                                          labelText: WaitlistStrings.capacity,
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
                                            (widget.form.capacity
                                                        ?.occupiedPeople ??
                                                    0) +
                                                (widget.form.capacity
                                                        ?.offeredPlaces ??
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
