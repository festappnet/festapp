import 'package:material_ui/material_ui.dart';

import '../../html/rich_html_editor_controller.dart';
import '../models/form_editor_draft.dart';
import '../presale_strings.dart';
import 'presale_content_editor.dart';

/// Both visitor pages share one collapsed section and one parent save.
class FormUnavailableContentEditor extends StatefulWidget {
  const FormUnavailableContentEditor({
    super.key,
    required this.form,
    required this.coordinator,
    required this.canEdit,
    required this.onChanged,
    required this.closedContent,
    this.loadSummary,
  });

  final FormEditorDraft form;
  final HtmlSaveCoordinator coordinator;
  final bool canEdit;
  final VoidCallback onChanged;
  final Widget closedContent;
  final Future<Map<String, dynamic>> Function(int)? loadSummary;

  @override
  State<FormUnavailableContentEditor> createState() =>
      FormUnavailableContentEditorState();
}

class FormUnavailableContentEditorState
    extends State<FormUnavailableContentEditor> {
  final _section = ExpansibleController();
  final _settings = ExpansibleController();
  bool _expanded = false;
  int _page = 0;

  void openNotifications() {
    setState(() => _page = 0);
    _section.expand();
    _settings.expand();
  }

  @override
  void dispose() {
    _section.dispose();
    _settings.dispose();
    super.dispose();
  }

  Widget _panel(int page, Widget child) => Offstage(
    offstage: _page != page,
    child: ExcludeFocus(
      excluding: !_expanded || _page != page,
      child: TickerMode(enabled: _expanded && _page == page, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const ValueKey('form-unavailable-section'),
    controller: _section,
    initiallyExpanded: false,
    maintainState: true,
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(
      PresaleStrings.unavailableContent,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      PresaleStrings.unavailableHelp,
      style: Theme.of(context).textTheme.bodySmall,
    ),
    onExpansionChanged: (value) => setState(() => _expanded = value),
    children: [
      ExcludeFocus(
        excluding: !_expanded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(PresaleStrings.beforeOpening),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(PresaleStrings.afterClosing),
                ),
              ],
              selected: {_page},
              onSelectionChanged: (value) {
                FocusScope.of(context).unfocus();
                setState(() => _page = value.single);
              },
            ),
            const SizedBox(height: 12),
            _panel(
              0,
              PresaleContentEditor(
                form: widget.form,
                coordinator: widget.coordinator,
                canEdit: widget.canEdit,
                onChanged: widget.onChanged,
                loadSummary: widget.loadSummary,
                settingsController: _settings,
                active: _expanded && _page == 0,
              ),
            ),
            _panel(1, widget.closedContent),
          ],
        ),
      ),
    ],
  );
}
