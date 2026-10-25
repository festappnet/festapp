import 'package:fstapp/widgets/app_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';

import 'html_strings.dart';
import 'html_embedded_block.dart';
import 'template_authoring.dart';
import 'html_text_style.dart';
import 'html_view.dart';
import 'rich_html_editor.dart';
import 'rich_html_editor_controller.dart';
import 'rich_html_editor_dialog.dart';

/// Inline Apply changes the parent draft. Only onSave or parent save persists.
class EditableHtmlField extends StatefulWidget {
  const EditableHtmlField({
    required this.html,
    this.embeddedBlock,
    required this.onChanged,
    this.owner = const HtmlMediaOwner.none(),
    this.profile = HtmlContentProfile.appContent,
    this.enabled = true,
    this.placeholder,
    this.fontSize = 18,
    this.onSave,
    this.coordinator,
    this.authoring,
    this.onDraftChanged,
    this.onCancel,
    this.twoFingersOn,
    this.twoFingersOff,
    super.key,
  });
  final TemplateAuthoringProvider? authoring;
  final VoidCallback? onCancel;
  final ValueChanged<RichHtmlEditorController?>? onDraftChanged;
  final String? html;
  final HtmlEmbeddedBlock? embeddedBlock;
  final String? placeholder;
  final ValueChanged<String> onChanged;
  final Future<void> Function(String)? onSave;
  final HtmlMediaOwner owner;
  final HtmlContentProfile profile;
  final bool enabled;
  final double fontSize;
  final HtmlSaveCoordinator? coordinator;
  final VoidCallback? twoFingersOn;
  final VoidCallback? twoFingersOff;
  @override
  State<EditableHtmlField> createState() => _EditableHtmlFieldState();
}

class _EditableHtmlFieldState extends State<EditableHtmlField> {
  RichHtmlEditorController? _controller;
  HtmlSaveCoordinator? _coordinator;
  Future<void> Function(String)? _writer;
  String _activationHtml = '';
  bool _active = false;
  bool _saving = false;
  bool _expanded = false;
  bool _confirmingCancel = false;
  bool _startedAuthoring = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedAuthoring && widget.authoring != null && widget.enabled) {
      _startedAuthoring = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_active) _begin();
      });
    }
  }

  void _begin() {
    _coordinator = widget.coordinator ?? HtmlEditingScope.maybeOf(context);
    _activationHtml = widget.html ?? '';
    _writer =
        widget.onSave; // Freeze the entity/version writer for this session.
    _controller ??= RichHtmlEditorController(
      initialHtml: _activationHtml,
      embeddedBlock: widget.embeddedBlock,
      owner: _coordinator == null && _writer == null
          ? const HtmlMediaOwner.none()
          : widget.owner,
      profile: widget.profile,
      media: _coordinator?.media,
      authoring: widget.authoring,
    );
    if (_controller!.html != _activationHtml)
      _controller!.reset(_activationHtml);
    _controller!.removeListener(_draftChanged);
    _controller!.addListener(_draftChanged);
    _coordinator?.registerActive(
      this,
      () {
        _coordinator?.recordValue(_controller!);
        widget.onChanged(_controller!.html);
      },
      // Sanitizing loaded HTML is not a user edit. Match the field's own
      // Save/Cancel controls instead of prompting for merely opening it.
      isDirty: () => _active && _controller!.hasUserChanges,
      acceptSave: () {
        if (mounted) setState(() => _active = false);
        _controller!.removeListener(_draftChanged);
        _coordinator?.unregisterActive(this);
      },
    );
    setState(() => _active = true);
    widget.onDraftChanged?.call(_controller);
  }

  void _draftChanged() {
    widget.onDraftChanged?.call(_controller);
    _coordinator?.draftChanged();
    if (mounted && _active) setState(() {});
  }

  Future<void> _requestCancel() async {
    if (_saving || _confirmingCancel || !_active) return;
    _confirmingCancel = true;
    final discard = !_controller!.hasUserChanges ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AppAlertDialog(
                onClose: () => Navigator.pop(context, false),
                title: Text(HtmlStrings.discardDraft),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(CommonStrings.storno),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(CommonStrings.ok),
                  ),
                ],
              ),
            ) ==
            true;
    _confirmingCancel = false;
    if (!mounted || !_active) return;
    if (discard) {
      _cancel();
    } else {
      _controller!.focusNode.requestFocus();
    }
  }

  void _cancel() {
    widget.onDraftChanged?.call(null);
    _controller!.removeListener(_draftChanged);
    _coordinator?.unregisterActive(this);
    _controller!.reset(_activationHtml);
    setState(() => _active = false);
  }

  Future<void> _apply() async {
    if (_saving || !_controller!.hasUserChanges) return;
    setState(() => _saving = true);
    final success = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        var html = _controller!.html;
        if (_writer != null) {
          html = await _controller!.prepareForSave(context: context);
          if (!mounted) return;
          await _writer!(html);
          if (!mounted) return;
        }
        _coordinator?.recordValue(_controller!);
        widget.onChanged(html);
      },
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (success) _active = false;
    });
    if (success) {
      _controller!.removeListener(_draftChanged);
      if (_writer != null) _coordinator?.markSaved(controller: _controller);
      _coordinator?.unregisterActive(this);
      _activationHtml = widget.html ?? _controller!.html;
      _controller!.reset(_activationHtml);
    }
  }

  Future<void> _expand() async {
    setState(() => _expanded = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final action = await RichHtmlEditorDialog.expand(context, _controller!,
        textStyle: htmlTextStyle(context, fontSize: widget.fontSize));
    if (!mounted) return;
    setState(() => _expanded = false);
    if (action == HtmlEditorFullscreenAction.save) {
      await _apply();
      return;
    }
    if (action == HtmlEditorFullscreenAction.cancel) {
      _cancel();
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _controller!.focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller?.removeListener(_draftChanged);
    _coordinator?.unregisterActive(this);
    _controller?.dispose();
    super.dispose();
  }

  Widget _editingActions() => widget.authoring != null
      ? IconButton(
          tooltip: HtmlStrings.expand,
          onPressed: _saving ? null : _expand,
          icon: const Icon(Icons.open_in_full))
      : Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            TextButton(
              onPressed: _saving ? null : _requestCancel,
              child: Text(CommonStrings.storno),
            ),
            FilledButton(
              onPressed:
                  _saving || !_controller!.hasUserChanges ? null : _apply,
              child: Text(CommonStrings.save),
            ),
            IconButton(
              tooltip: HtmlStrings.expand,
              onPressed: _saving ? null : _expand,
              icon: const Icon(Icons.open_in_full),
            ),
          ],
        );

  @override
  Widget build(BuildContext context) {
    if (!_active) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: HtmlView(
              embeddedBlock: widget.embeddedBlock,
              html: (widget.html?.isNotEmpty ?? false)
                  ? widget.html!
                  : widget.placeholder ?? '',
              fontSize: widget.fontSize,
              twoFingersOn: widget.twoFingersOn,
              twoFingersOff: widget.twoFingersOff,
              imageBytesResolver: (_coordinator ??
                      widget.coordinator ??
                      HtmlEditingScope.maybeOf(context))
                  ?.media
                  .previewBytes,
            ),
          ),
          if (widget.enabled)
            IconButton(
              tooltip: CommonStrings.edit,
              icon: const Icon(Icons.edit),
              onPressed: _begin,
            ),
        ],
      );
    }
    return CallbackShortcuts(
      bindings: {
        if (widget.authoring == null)
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_expanded && ModalRoute.of(context)?.isCurrent != false) {
              _requestCancel();
            }
          },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_expanded) _editingActions(),
            const SizedBox(height: 8),
            if (!_expanded)
              RichHtmlEditor(
                controller: _controller!,
                textStyle: htmlTextStyle(context, fontSize: widget.fontSize),
                onCancel: widget.onCancel ?? (widget.authoring == null ? _requestCancel : null),
                toolbarActions: _editingActions(),
                enabled: !_saving && widget.enabled,
              ),
          ],
        ),
      ),
    );
  }
}
