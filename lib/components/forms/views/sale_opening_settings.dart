import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/locale_date_time.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../models/form_editor_draft.dart';
import '../models/form_presentation.dart';
import '../sale_opening_strings.dart';
import '../widgets_view/countdown_content.dart';
import 'sale_opening_subscribers.dart';

/// Changes only the supplied draft. The surrounding editor owns persistence.
class SaleOpeningSettings extends StatefulWidget {
  const SaleOpeningSettings({
    super.key,
    required this.form,
    required this.canEdit,
    required this.onChanged,
    this.onEditEmails,
    this.loadSummary,
    this.enableBaseline,
  });
  final FormEditorDraft form;
  final FormDefinition? enableBaseline;
  final bool canEdit;
  final VoidCallback onChanged;
  final VoidCallback? onEditEmails;
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
    final definition = widget.form.definition;
    widget.form.definition = definition
        .withSaleOpening(enabled: true, paused: false)
        .withCountdownTitle(
          insertSaleOpeningBlock(
            definition.enableCountdown
                ? countdownContent(definition.countdownTitle)
                : definition.countdownTitle ?? '',
          ),
        );
    widget.onChanged();
  }

  void _pause() {
    widget.form.definition = widget.form.definition.withSaleOpening(
      paused: true,
    );
    widget.onChanged();
  }

  Future<void> _end() async {
    if (!initiallyEnabled) {
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(SaleOpeningStrings.end),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    widget.form.definition = widget.form.definition.withSaleOpening(
      enabled: false,
      paused: false,
    );
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
        status = SaleOpeningStrings.text('offState');
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
            form.isOpen != true
                ? SaleOpeningStrings.text('formClosedState')
                : form.startTime != null
                ? SaleOpeningStrings.configuredStart(
                    LocaleDateTime.dateTimeCell(
                      form.startTime!,
                      Localizations.localeOf(context).toString(),
                    ),
                  )
                : SaleOpeningStrings.requiresStart,
          ),
          const SizedBox(height: 16),
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
            Text(status, style: Theme.of(context).textTheme.titleMedium),
            if (enabled && !terminal) ...[
              const SizedBox(height: 8),
              Text(SaleOpeningStrings.dateChange),
            ],
            if (!terminal && eligible && widget.canEdit) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: !enabled || form.saleOpeningPaused
                    ? FilledButton(
                        onPressed: _collect,
                        child: Text(
                          SaleOpeningStrings.text(
                            enabled ? 'resumeAction' : 'enableAction',
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: _pause,
                        child: Text(SaleOpeningStrings.pause),
                      ),
              ),
            ],
            if (!enabled && !terminal && !future)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(SaleOpeningStrings.requiresStart),
              ),
            if (enabled && widget.form.definition.id != null) ...[
              const Divider(height: 32),
              Text(
                '${SaleOpeningStrings.text('subscriberCount')}: ${(snapshot.data?['subscribers'] as Map?)?['active'] ?? 0}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (RightsService.hasCapability(
                    AuthorizationCapabilities.formsSaleOpeningSubscribersRead,
                  ))
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => AppDialog(
                          child: SaleOpeningSubscribers(formId: form.id!),
                        ),
                      ),
                      child: Text(SaleOpeningStrings.subscribers),
                    ),
                  if (widget.onEditEmails != null)
                    TextButton(
                      onPressed: widget.onEditEmails,
                      child: Text(SaleOpeningStrings.editEmails),
                    ),
                ],
              ),
            ],
            if (enabled && !terminal && widget.canEdit) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _end,
                  child: Text(
                    initiallyEnabled
                        ? SaleOpeningStrings.end
                        : SaleOpeningStrings.text('undoEnable'),
                  ),
                ),
              ),
            ],
          ],
        ],
      );
    },
  );
}
