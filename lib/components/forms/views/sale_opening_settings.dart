import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../models/form_editor_draft.dart';
import '../presale_content_draft.dart';
import '../sale_opening_strings.dart';
import '../presale_strings.dart';
import 'sale_opening_subscribers.dart';

/// Changes only the supplied draft. The surrounding editor owns persistence.
class SaleOpeningSettings extends StatefulWidget {
  const SaleOpeningSettings({
    super.key,
    required this.form,
    required this.canEdit,
    required this.onChanged,
    this.loadSummary,
    this.enableBaseline,
    this.onCollect,
    this.onPause,
    this.onEnd,
  });
  final VoidCallback? onCollect, onPause, onEnd;
  final FormEditorDraft form;
  final FormDefinition? enableBaseline;
  final bool canEdit;
  final VoidCallback onChanged;
  final Future<Map<String, dynamic>> Function(int)? loadSummary;
  @override
  State<SaleOpeningSettings> createState() => _SaleOpeningSettingsState();
}

class _SaleOpeningSettingsState extends State<SaleOpeningSettings> {
  late Future<Map<String, dynamic>> summary;
  late bool initiallyEnabled;
  late FormDefinition initialDefinition;
  @override
  void initState() {
    super.initState();
    initialDefinition = widget.enableBaseline ?? widget.form.definition;
    initiallyEnabled = initialDefinition.saleOpeningEnabled;
    summary = _loadSummary();
  }

  Future<Map<String, dynamic>> _loadSummary() async {
    final id = widget.form.definition.id;
    if (id == null) return {};
    if (widget.loadSummary != null) return widget.loadSummary!(id);
    return Map<String, dynamic>.from(
      await Supabase.instance.client.rpc(
        'get_sale_opening_summary',
        params: {'p_form': id},
      ),
    );
  }

  void _collect() {
    if (widget.onCollect != null) {
      widget.onCollect!();
      widget.onChanged();
      return;
    }
    widget.form.definition = PresaleContentDraft.collectDefinition(
      widget.form.definition,
    );
    widget.onChanged();
  }

  void _pause() {
    if (widget.onPause != null) {
      widget.onPause!();
      widget.onChanged();
      return;
    }
    widget.form.definition = widget.form.definition.withSaleOpening(
      paused: true,
    );
    widget.onChanged();
  }

  Future<void> _end() async {
    if (!initiallyEnabled) {
      if (widget.onEnd != null) {
        widget.onEnd!();
        widget.onChanged();
        return;
      }
      widget.form.definition = initialDefinition;
      widget.onChanged();
      return;
    }
    if (initiallyEnabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
          title: Text(SaleOpeningStrings.end),
          content: Text(SaleOpeningStrings.endConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(CommonStrings.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(SaleOpeningStrings.end),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    if (widget.onEnd != null) {
      widget.onEnd!();
    } else {
      widget.form.definition = widget.form.definition.withSaleOpening(
        enabled: false,
        paused: false,
      );
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: summary,
    builder: (context, snapshot) {
      final form = widget.form.definition;
      final enabled = form.saleOpeningEnabled;
      final phase = snapshot.data?['phase'];
      final terminal = phase == 'cancelled' || phase == 'completed';
      final future = form.startTimeUtc?.isAfter(DateTime.now()) == true;
      final eligible = future && form.isOpen == true;
      final loaded =
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError;
      String status;
      if (phase == 'cancelled')
        status = SaleOpeningStrings.text('endedState');
      else if (phase == 'completed')
        status = SaleOpeningStrings.text('processedState');
      else if (!enabled)
        status = SaleOpeningStrings.text(
          initiallyEnabled ? 'pendingEndState' : 'offState',
        );
      else if (form.isOpen != true)
        status = SaleOpeningStrings.text('manualClosedState');
      else if (form.startTimeUtc == null)
        status = SaleOpeningStrings.requiresStart;
      else if (phase == 'dispatching' || snapshot.data?['openedAt'] != null)
        status = SaleOpeningStrings.text('processingState');
      else if (!future)
        status = SaleOpeningStrings.text('waitingState');
      else if (form.saleOpeningPaused)
        status = SaleOpeningStrings.text('pausedState');
      else
        status = SaleOpeningStrings.text('collectingState');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            PresaleStrings.email,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (!loaded && !snapshot.hasError)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (snapshot.hasError) ...[
            Text(SaleOpeningStrings.text('summaryFailed')),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  summary = _loadSummary();
                }),
                child: Text(CommonStrings.retry),
              ),
            ),
          ] else ...[
            if (enabled && eligible && !terminal) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(PresaleStrings.collectionLabel),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    form.saleOpeningPaused
                        ? PresaleStrings.collectionPausedHint
                        : PresaleStrings.collectionHint,
                  ),
                ),
                value: !form.saleOpeningPaused,
                onChanged: widget.canEdit
                    ? (collect) => collect ? _collect() : _pause()
                    : null,
              ),
            ] else ...[
              Text(
                !terminal && !enabled && !eligible
                    ? form.isOpen != true
                          ? SaleOpeningStrings.text('formClosedState')
                          : SaleOpeningStrings.requiresStart
                    : status,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!enabled && !terminal && eligible && widget.canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _collect,
                      child: Text(SaleOpeningStrings.text('enableAction')),
                    ),
                  ),
                ),
            ],
            if ((enabled || terminal) && form.id != null) ...[
              const SizedBox(height: 16),
              if (RightsService.hasCapability(
                AuthorizationCapabilities.formsSaleOpeningSubscribersRead,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${PresaleStrings.recipients} (${(snapshot.data?['subscribers'] as Map?)?['active'] ?? 0})',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => AppDialog(
                      child: SaleOpeningSubscribers(formId: form.id!),
                    ),
                  ),
                )
              else
                Text(
                  '${PresaleStrings.recipients}: ${(snapshot.data?['subscribers'] as Map?)?['active'] ?? 0}',
                ),
            ],
            if (enabled && !terminal && widget.canEdit) ...[
              const SizedBox(height: 8),
              if (initiallyEnabled)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  title: Text(
                    SaleOpeningStrings.text('endDetails'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  children: [
                    Text(SaleOpeningStrings.endConfirm),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _end,
                        child: Text(SaleOpeningStrings.end),
                      ),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _end,
                    child: Text(SaleOpeningStrings.text('undoEnable')),
                  ),
                ),
            ],
          ],
        ],
      );
    },
  );
}
