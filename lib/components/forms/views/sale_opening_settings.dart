import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../models/form_editor_draft.dart';
import '../sale_opening_strings.dart';
import '../widgets_view/countdown_content.dart';
import 'sale_opening_subscribers.dart';

/// Uses the form draft and its existing receipted Save/Cancel boundary.
class SaleOpeningSettings extends StatefulWidget {
  const SaleOpeningSettings({
    super.key,
    required this.form,
    required this.canEdit,
    required this.onChanged,
    this.onEditEmails,
  });
  final FormEditorDraft form;
  final bool canEdit;
  final VoidCallback onChanged;
  final VoidCallback? onEditEmails;
  @override
  State<SaleOpeningSettings> createState() => _SaleOpeningSettingsState();
}

class _SaleOpeningSettingsState extends State<SaleOpeningSettings> {
  late Future<dynamic> summary;
  String? phase;
  bool summaryLoaded = false, summaryFailed = false;
  int summaryGeneration = 0;
  @override
  void initState() {
    super.initState();
    summary = _loadSummary();
  }

  @override
  void didUpdateWidget(covariant SaleOpeningSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.form, widget.form)) {
      summaryLoaded = false;
      summaryFailed = false;
      summary = _loadSummary();
    }
  }

  Future<dynamic> _loadSummary() async {
    final generation = ++summaryGeneration;
    if (widget.form.definition.id == null) return <String, dynamic>{};
    try {
      final result = await Supabase.instance.client.rpc(
        'get_sale_opening_summary',
        params: {'p_form': widget.form.definition.id},
      );
      if (mounted && generation == summaryGeneration) {
        setState(() {
          phase = result['phase'] as String?;
          summaryLoaded = true;
        });
      }
      return result;
    } catch (_) {
      if (mounted && generation == summaryGeneration)
        setState(() => summaryFailed = true);
      return <String, dynamic>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final enabled = form.definition.saleOpeningEnabled;
    final eligible =
        form.definition.startTimeUtc?.isAfter(DateTime.now()) == true &&
        form.definition.isOpen == true;
    final terminal = phase == 'cancelled' || phase == 'completed';
    final canEnable =
        eligible &&
        !terminal &&
        !summaryFailed &&
        (summaryLoaded || form.definition.id == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(SaleOpeningStrings.enable),
          subtitle: Text(
            terminal
                ? SaleOpeningStrings.closed
                : summaryFailed
                ? SaleOpeningStrings.failed
                : eligible
                ? SaleOpeningStrings.explanation
                : SaleOpeningStrings.requiresStart,
          ),
          value: enabled,
          onChanged: widget.canEdit && canEnable && !enabled
              ? (value) {
                  form.definition = form.definition
                      .withSaleOpening(enabled: value, paused: false)
                      .withCountdownTitle(
                        insertSaleOpeningBlock(
                          form.definition.enableCountdown
                              ? countdownContent(form.definition.countdownTitle)
                              : form.definition.countdownTitle ?? '',
                        ),
                      );
                  widget.onChanged();
                }
              : null,
        ),
        if (enabled) ...[
          Text(SaleOpeningStrings.dateChange),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(SaleOpeningStrings.pause),
            value: form.definition.saleOpeningPaused,
            onChanged: widget.canEdit
                ? (value) {
                    form.definition = form.definition.withSaleOpening(
                      paused: value,
                    );
                    widget.onChanged();
                  }
                : null,
          ),
          FutureBuilder<dynamic>(
            future: summary,
            builder: (context, snapshot) {
              final value = snapshot.data as Map?;
              final contacts = value?['subscribers'] as Map? ?? {};
              final messages = value?['messages'] as Map? ?? {};
              int count(List<String> states) => states.fold(
                0,
                (sum, key) => sum + ((messages[key] as num?)?.toInt() ?? 0),
              );
              return Wrap(
                spacing: 12,
                children: [
                  for (final item in [
                                        ('active', SaleOpeningStrings.active),
                    ('unsubscribed', SaleOpeningStrings.unsubscribed),
                    ('closed', SaleOpeningStrings.closed),
                  ])
                    Text('${item.$2}: ${contacts[item.$1] ?? 0}'),
                  Text(
                    '${SaleOpeningStrings.queued}: ${count(['pending', 'preparing', 'retry_wait', 'blocked'])}',
                  ),
                  Text(
                    '${SaleOpeningStrings.accepted}: ${count(['accepted'])}',
                  ),
                  Text(
                    '${SaleOpeningStrings.delivered}: ${count(['delivery'])}',
                  ),
                  Text(
                    '${SaleOpeningStrings.error}: ${count(['dead', 'unknown', 'suppressed', 'bounce', 'complaint', 'reject', 'rendering_failure'])}',
                  ),
                ],
              );
            },
          ),
          Wrap(
            children: [
              if (RightsService.hasCapability(
                AuthorizationCapabilities.formsSaleOpeningSubscribersRead,
              ))
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AppDialog(
                      child: SaleOpeningSubscribers(
                        formId: form.definition.id!,
                      ),
                    ),
                  ),
                  child: Text(SaleOpeningStrings.subscribers),
                ),
              if (widget.onEditEmails != null)
                TextButton(
                  onPressed: widget.onEditEmails,
                  child: Text(SaleOpeningStrings.editEmails),
                ),
              TextButton(
                onPressed: !widget.canEdit
                    ? null
                    : () async {
                        final ended = await showDialog<bool>(
                          context: context,
                          builder: (context) => AppAlertDialog(
                            title: Text(SaleOpeningStrings.end),
                            content: Text(SaleOpeningStrings.endConfirm),
                            onClose: () => Navigator.pop(context, false),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(SaleOpeningStrings.end),
                              ),
                            ],
                          ),
                        );
                        if (ended == true) {
                          form.definition = form.definition.withSaleOpening(
                            enabled: false,
                          );
                          widget.onChanged();
                        }
                      },
                child: Text(SaleOpeningStrings.end),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
