import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';

import 'html_media_service.dart';
import 'html_strings.dart';
import 'rich_html_editor.dart';
import 'rich_html_editor_controller.dart';

enum HtmlEditorFullscreenAction { save, cancel, collapse }

class RichHtmlEditorDialog extends StatefulWidget {
  const RichHtmlEditorDialog._({
    required this.controller,
    this.title,
    this.textStyle,
    this.ownsController = true,
    this.fullPage = false,
  });
  final RichHtmlEditorController controller;
  final String? title;
  final TextStyle? textStyle;
  final bool ownsController;
  final bool fullPage;

  static Future<String?> show(
    BuildContext context, {
    String? initialHtml,
    Future<String?> Function()? loadHtml,
    String? title,
    HtmlMediaOwner owner = const HtmlMediaOwner.none(),
    HtmlContentProfile profile = HtmlContentProfile.appContent,
    HtmlSaveCoordinator? coordinator,
    HtmlMediaDraft? media,
  }) async {
    String? html = initialHtml;
    if (html == null && loadHtml != null) {
      var loaded = false;
      await ExceptionHandler.guardVoid(
        context,
        futureFunction: () async {
          html = await loadHtml();
          loaded = true;
        },
      );
      if (!loaded || !context.mounted) return null;
    }
    if (!context.mounted) return null;
    coordinator ??= HtmlEditingScope.maybeOf(context);
    final draftMedia = media ?? coordinator?.media;
    final controller = RichHtmlEditorController(
      initialHtml: html,
      owner: draftMedia == null ? const HtmlMediaOwner.none() : owner,
      profile: profile,
      media: draftMedia,
    );
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          RichHtmlEditorDialog._(controller: controller, title: title),
    );
    if (result != null) coordinator?.recordValue(controller);
    return result;
  }

  static Future<HtmlEditorFullscreenAction> expand(
    BuildContext context,
    RichHtmlEditorController controller, {
    TextStyle? textStyle,
  }) async {
    final route = PageRouteBuilder<HtmlEditorFullscreenAction>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) => RichHtmlEditorDialog._(
        controller: controller,
        ownsController: false,
        fullPage: true,
        textStyle: textStyle,
      ),
    );
    final action = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<HtmlEditorFullscreenAction>(route);
    // The inline editor must not remount until the page's exit transition
    // removes its editor: both share the document layout key and IME client.
    await route.completed;
    return action ?? HtmlEditorFullscreenAction.collapse;
  }

  @override
  State<RichHtmlEditorDialog> createState() => _RichHtmlEditorDialogState();
}

class _RichHtmlEditorDialogState extends State<RichHtmlEditorDialog> {
  bool _expanded = false;
  bool _confirmingCancel = false;
  bool get _fullPage => widget.fullPage || _expanded;

  void _finish(bool save) {
    if (widget.ownsController) {
      Navigator.pop<String>(context, save ? widget.controller.html : null);
    } else {
      Navigator.pop<HtmlEditorFullscreenAction>(
        context,
        save
            ? HtmlEditorFullscreenAction.save
            : HtmlEditorFullscreenAction.cancel,
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    if (widget.fullPage) {
      Navigator.pop<HtmlEditorFullscreenAction>(
        context,
        HtmlEditorFullscreenAction.collapse,
      );
      return;
    }
    setState(() => _expanded = !_expanded);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) widget.controller.focusNode.requestFocus();
  }

  Future<bool> _canClose() async {
    if (_confirmingCancel) return false;
    if (!widget.controller.hasUserChanges) return true;
    _confirmingCancel = true;
    final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
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
    if (mounted && !discard) widget.controller.focusNode.requestFocus();
    return discard;
  }

  Future<void> _requestCancel() async {
    if (await _canClose() && mounted) _finish(false);
  }

  @override
  void dispose() {
    if (widget.ownsController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final small = MediaQuery.sizeOf(context).width < 650;
        final content = SafeArea(
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.title ?? CommonStrings.edit),
              actions: [
                if (_fullPage)
                  Builder(
                    builder: (context) => TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: IconTheme.of(context).color,
                      ),
                      onPressed: _toggleFullscreen,
                      icon: const Icon(Icons.close_fullscreen),
                      label: Text(HtmlStrings.collapse),
                    ),
                  )
                else
                  IconButton(
                    tooltip: HtmlStrings.expand,
                    onPressed: _toggleFullscreen,
                    icon: const Icon(Icons.open_in_full),
                  ),
              ],
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  if (await _canClose() && context.mounted) _finish(false);
                },
              ),
            ),
            body: _fullPage
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: RichHtmlEditor(
                      controller: widget.controller,
                      textStyle: widget.textStyle,
                      onCancel: _requestCancel,
                      fullscreen: true,
                    ),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: small ? double.infinity : 1000,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: RichHtmlEditor(
                              controller: widget.controller,
                              textStyle: widget.textStyle,
                              onCancel: _requestCancel),
                        ),
                      ),
                    ),
                  ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () async {
                        if (await _canClose() && context.mounted)
                          _finish(false);
                      },
                      child: Text(CommonStrings.storno),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: widget.controller.hasUserChanges
                          ? () => _finish(true)
                          : null,
                      child: Text(CommonStrings.save),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _requestCancel,
          },
          child: PopScope(
            canPop: !widget.ownsController || !widget.controller.isDirty,
            onPopInvokedWithResult: (didPop, _) async {
              if (!didPop && await _canClose() && context.mounted)
                Navigator.pop(context);
            },
            child: _fullPage
                ? content
                : small
                    ? Dialog.fullscreen(child: content)
                    : Dialog(
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox(
                          width: 1000,
                          height: MediaQuery.sizeOf(context).height * 0.85,
                          child: content,
                        ),
                      ),
          ),
        );
      },
    );
  }
}
