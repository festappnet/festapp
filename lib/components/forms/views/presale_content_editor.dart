import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/html/html_embedded_block.dart';

import '../widgets_view/countdown_widget.dart';
import '../widgets_view/sale_opening_notification.dart';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/html_text_style.dart';

import '../models/form_editor_draft.dart';
import '../models/form_presentation.dart';
import '../presale_content_draft.dart';
import '../form_appearance_theme.dart';
import '../presale_strings.dart';
import '../sale_opening_strings.dart';
import '../../_shared/common_strings.dart';
import '../widgets_view/presale_content.dart';
import 'sale_opening_settings.dart';

/// One persistent session, even when customization is collapsed. Parent Save
/// flushes media and this same draft; opening either view is presentation only.
class PresaleContentEditor extends StatefulWidget {
  const PresaleContentEditor({
    super.key,
    required this.form,
    required this.coordinator,
    this.loadSummary,
    this.settingsController,
    this.active = true,
    required this.canEdit,
    required this.onChanged,
  });
  final Future<Map<String, dynamic>> Function(int)? loadSummary;
  final ExpansibleController? settingsController;
  final bool active;
  final FormEditorDraft form;
  final HtmlSaveCoordinator coordinator;
  final bool canEdit;
  final VoidCallback onChanged;
  @override
  State<PresaleContentEditor> createState() => _PresaleContentEditorState();
}

class _PresaleContentEditorState extends State<PresaleContentEditor> {
  bool editing = false;
  bool settingsExpanded = false;
  bool mobile = false;
  bool _collectionEligible = false;
  late Future<Map<String, dynamic>> _summary;
  late RichHtmlEditorController editor;
  late PresaleContentDraft draft;
  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final d = widget.form.definition;
    _summary = _fetchSummary();
    var previousHtml = d.presaleContent ?? '';
    editor = RichHtmlEditorController(
      initialHtml: d.enableCountdown
          ? countdownContent(d.presaleContent)
          : d.presaleContent ?? '',
      owner: HtmlMediaOwner.occasion(d.occasionId),
      media: widget.coordinator.media,
      allowEmbeddedInsertion: false,
      embeddedBlocks: [
        HtmlEmbeddedBlock(
          cssClass: 'form-countdown',
          label: PresaleStrings.countdown,
          builder: (_) =>
              widget.form.definition.enableCountdown &&
                  widget.form.definition.startTime != null
              ? CountdownWidget(
                  targetTime: widget.form.definition.startTime!,
                  onFinished: () {},
                  compact: true,
                )
              : const SizedBox.shrink(),
        ),
        HtmlEmbeddedBlock(
          cssClass: 'form-sale-opening-notification',
          label: PresaleStrings.email,
          builder: (_) =>
              _collectionEligible &&
                  widget.form.definition.saleOpeningEnabled &&
                  !widget.form.definition.saleOpeningPaused
              ? const SaleOpeningNotification(formLink: '', preview: true)
              : Text(PresaleStrings.paused),
        ),
      ],
      historyBinding: PresaleContentDraft.binding(widget.form, () {
        final current = widget.form.definition.presaleContent ?? '';
        final removed =
            hasPresaleSlot(previousHtml, 'form-sale-opening-notification') &&
            !hasPresaleSlot(current, 'form-sale-opening-notification');
        previousHtml = current;
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            messenger?.hideCurrentSnackBar();
            if (removed) {
              final revision = editor.revision;
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(PresaleStrings.removed),
                  action: SnackBarAction(
                    label: PresaleStrings.undo,
                    onPressed: () {
                      if (editor.revision == revision) editor.undo();
                    },
                  ),
                ),
              );
            }
          });
        }
        widget.onChanged();
        if (mounted) setState(() {});
      }),
    );
    draft = PresaleContentDraft(widget.form, editor: editor);
    widget.coordinator.registerActive(this, () {
      if (editor.hasUserChanges) {
        widget.coordinator.recordValue(editor);
        widget.form.definition = widget.form.definition.withPresaleContent(
          presaleEditedHtml(editor.html, d.presaleContent),
        );
      }
    }, isDirty: () => editor.hasUserChanges);
  }

  Future<Map<String, dynamic>> _fetchSummary() async {
    final id = widget.form.definition.id;
    if (id == null) return {};
    if (widget.loadSummary != null) return widget.loadSummary!(id);
    return Map<String, dynamic>.from(
      await Supabase.instance.client.rpc(
        'get_sale_opening_summary',
        params: {'p_form': id},
      ) as Map,
    );
  }

  @override
  void didUpdateWidget(covariant PresaleContentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) editor.focusNode.unfocus();
    if (oldWidget.form != widget.form) {
      oldWidget.coordinator.unregisterActive(this);
      editor.dispose();
      _attach();
    }
  }

  Future<void> _recover() async {
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        final archive = await Supabase.instance.client.rpc(
          'get_form_presale_archive',
          params: {'p_form': widget.form.definition.id},
        );
        if (!mounted) return;
        final html = archive?['secondaryHtml'] as String?;
        if (html == null || html.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(PresaleStrings.noArchive)));
          return;
        }
        editor.appendHtml(inertPresaleSecondary(html));
      },
    );
  }

  @override
  void dispose() {
    widget.coordinator.unregisterActive(this);
    editor.dispose();
    super.dispose();
  }

  Widget _visitorPreview(ThemeData theme) {
    final d = widget.form.definition;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: mobile ? 375 : 800),
        child: Container(
          key: const ValueKey('presale-preview-surface'),
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
          child: Theme(
            data: theme,
            child: Material(
              color: theme.scaffoldBackgroundColor,
              child: DecoratedBox(
                decoration:
                    formAppearanceBackground(theme, d) ?? const BoxDecoration(),
                child: DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  child: d.startTime == null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(PresaleStrings.requiresStart),
                        )
                      : PresaleContent(
                          targetTime: d.startTime!,
                          onFinished: () {},
                          html: d.presaleContent,
                          showTimer: d.enableCountdown,
                          canSubscribe:
                              _collectionEligible &&
                              d.saleOpeningEnabled &&
                              !d.saleOpeningPaused,
                          header: d.presaleHeader,
                          eventTitle:
                              widget.form.occasionModel?.title ?? d.title,
                          preview: true,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.form.definition;
    final theme = formAppearanceTheme(formAppearanceBaseTheme(context, d), d);
    return FutureBuilder<Map<String, dynamic>>(
      future: _summary,
      builder: (context, summary) {
        final terminal = [
          'cancelled',
          'completed',
        ].contains(summary.data?['phase']);
        _collectionEligible =
            summary.hasData &&
            !terminal &&
            d.isOpen == true &&
            d.startTimeUtc?.isAfter(DateTime.now()) == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Offstage(
              offstage: editing,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.withValues(alpha: .2)
                      : Colors.grey.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white24
                        : Colors.grey.withValues(alpha: .3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _visitorPreview(theme)),
                    if (widget.canEdit)
                      IconButton(
                        key: const ValueKey('presale-edit-content'),
                        tooltip: CommonStrings.editContent,
                        icon: const Icon(Icons.edit),
                        onPressed: () => setState(() => editing = true),
                      ),
                  ],
                ),
              ),
            ),
            Offstage(
              offstage: !editing,
              child: ExcludeFocus(
                excluding: !widget.active || !editing,
                child: TickerMode(
                  enabled: widget.active && editing,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RichHtmlEditor(
                        controller: editor,
                        enabled: widget.canEdit,
                        textStyle: htmlTextStyle(context, fontSize: 24),
                        toolbarActions: TextButton(
                          key: const ValueKey('presale-edit-done'),
                          onPressed: () {
                            editor.focusNode.unfocus();
                            setState(() => editing = false);
                          },
                          child: Text(PresaleStrings.done),
                        ),
                      ),
                      Text(
                        PresaleStrings.saveHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              key: const ValueKey('presale-settings'),
              controller: widget.settingsController,
              initiallyExpanded: false,
              maintainState: true,
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              onExpansionChanged: (value) =>
                  setState(() => settingsExpanded = value),
              title: Text(PresaleStrings.settings),
              subtitle: Text(
                !d.saleOpeningEnabled || terminal
                    ? PresaleStrings.emailOff
                    : d.saleOpeningPaused
                    ? PresaleStrings.emailPaused
                    : PresaleStrings.emailOn,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                ExcludeFocus(
                  excluding: !widget.active || !settingsExpanded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SaleOpeningSettings(
                        key: ObjectKey(widget.form),
                        form: widget.form,
                        loadSummary: (_) {
                          if (summary.hasError)
                            setState(() => _summary = _fetchSummary());
                          return _summary;
                        },
                        canEdit: widget.canEdit,
                        onCollect: draft.collect,
                        onPause: draft.pause,
                        onEnd: draft.end,
                        onChanged: () {
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: d.presaleHeader,
                        decoration: InputDecoration(
                          labelText: PresaleStrings.header,
                        ),
                        items: [
                          for (final key in ['event_and_date', 'date', 'none'])
                            DropdownMenuItem(
                              value: key,
                              child: Text(PresaleStrings.headerOption(key)),
                            ),
                        ],
                        onChanged: widget.canEdit
                            ? (value) => draft.header(value!)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(PresaleStrings.countdown),
                        value: d.enableCountdown,
                        onChanged: widget.canEdit && d.startTime != null
                            ? draft.countdown
                            : null,
                      ),
                      Text(
                        SaleOpeningStrings.dateChange,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(PresaleStrings.mobile),
                        value: mobile,
                        onChanged: (value) => setState(() => mobile = value),
                      ),
                      if (widget.canEdit && d.id != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _recover,
                            child: Text(PresaleStrings.recover),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
