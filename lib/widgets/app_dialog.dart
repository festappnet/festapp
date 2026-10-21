import 'package:flutter/material.dart';
import 'package:venue_seat_picker/editor_ui.dart' show EditorDialogDismissal;
import 'package:fstapp/components/_shared/common_strings.dart';

/// Shared appearance and keyboard dismissal for application modals.
const appDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
  side: BorderSide(color: Color(0x33FFFFFF)),
);

class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    this.title,
    this.actions = const [],
    this.onClose,
    this.closeEnabled = true,
  });

  final Widget? title;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool closeEnabled;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: DefaultTextStyle.of(context).style.color),
              textAlign: TextAlign.center,
              child: title ?? const SizedBox.shrink(),
            ),
          ),
          ...actions,
          IconButton(
            tooltip: CommonStrings.close,
            icon: const Icon(Icons.close),
            onPressed: closeEnabled
                ? onClose ?? () => Navigator.of(context).maybePop()
                : null,
          ),
        ],
      );
}

/// Optional secondary information stays readable above actions on small screens.
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({super.key, this.leading, required this.actions});

  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final buttons = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: actions,
    );
    if (leading == null) return buttons;
    if (MediaQuery.sizeOf(context).width < 650) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [leading!, const SizedBox(height: 8), buttons],
      );
    }
    return Row(children: [
      Expanded(child: leading!),
      const SizedBox(width: 8),
      Expanded(child: buttons),
    ]);
  }
}

/// Keeps focus inside the modal, including before an input receives focus.
/// maybePop preserves the caller's PopScope and draft confirmation.
class AppDialogDismissal extends StatelessWidget {
  const AppDialogDismissal(
      {super.key,
      required this.child,
      this.onClose,
      this.enabled = true,
      this.autofocus = true});
  final Widget child;
  final VoidCallback? onClose;
  final bool enabled, autofocus;
  @override
  Widget build(BuildContext context) => EditorDialogDismissal(
      onClose: onClose, enabled: enabled, autofocus: autofocus, child: child);
}

class AppDialogAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppDialogAppBar({
    super.key,
    this.title,
    this.actions = const [],
    this.onClose,
    this.closeEnabled = true,
  });

  final Widget? title;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool closeEnabled;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        automaticallyImplyLeading: false,
        title: AppDialogHeader(
          title: title,
          actions: actions,
          onClose: onClose,
          closeEnabled: closeEnabled,
        ),
      );
}

/// For custom content such as canvases, search panels and full-page editors.
class AppDialog extends Dialog {
  const AppDialog({
    super.key,
    super.child,
    super.backgroundColor,
    super.elevation = 16,
    super.shadowColor,
    super.surfaceTintColor,
    super.insetAnimationDuration,
    super.insetAnimationCurve,
    super.insetPadding,
    super.clipBehavior,
    super.shape = appDialogShape,
    super.alignment,
    super.constraints,
    super.semanticsRole,
    this.onClose,
    this.dismissible = true,
  }) : _fullscreen = false;

  const AppDialog.fullscreen({
    super.key,
    super.child,
    super.backgroundColor,
    super.insetAnimationDuration,
    super.insetAnimationCurve,
    this.onClose,
    this.dismissible = true,
  })  : _fullscreen = true,
        super.fullscreen();

  final VoidCallback? onClose;
  final bool dismissible;
  final bool _fullscreen;

  @override
  Widget build(BuildContext context) => AppDialogDismissal(
        onClose: onClose,
        enabled: dismissible,
        child: _fullscreen
            ? Dialog.fullscreen(
                backgroundColor: backgroundColor,
                insetAnimationDuration: insetAnimationDuration,
                insetAnimationCurve: insetAnimationCurve,
                semanticsRole: semanticsRole,
                child: child,
              )
            : Dialog(
                backgroundColor: backgroundColor,
                elevation: elevation,
                shadowColor: shadowColor,
                surfaceTintColor: surfaceTintColor,
                insetAnimationDuration: insetAnimationDuration,
                insetAnimationCurve: insetAnimationCurve,
                insetPadding: insetPadding,
                clipBehavior: clipBehavior,
                shape: shape,
                alignment: alignment,
                constraints: constraints,
                semanticsRole: semanticsRole,
                child: child,
              ),
      );
}

/// Forms, confirmations and settings use the same title and close placement.
class AppAlertDialog extends AlertDialog {
  AppAlertDialog({
    super.key,
    Widget? title,
    super.icon,
    super.iconPadding,
    super.iconColor,
    super.titlePadding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
    super.titleTextStyle,
    super.content,
    super.contentPadding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
    super.contentTextStyle,
    super.actions,
    super.actionsPadding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    super.actionsAlignment,
    super.actionsOverflowAlignment,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing,
    super.buttonPadding,
    super.backgroundColor,
    super.elevation = 16,
    super.shadowColor,
    super.surfaceTintColor,
    super.semanticLabel,
    super.insetPadding,
    super.clipBehavior,
    super.shape = appDialogShape,
    super.alignment,
    super.constraints,
    super.scrollable,
    this.onClose,
    this.dismissible = true,
  }) : super(
          title: AppDialogHeader(
            title: title,
            onClose: onClose,
            closeEnabled: dismissible,
          ),
        );

  final VoidCallback? onClose;
  final bool dismissible;

  @override
  Widget build(BuildContext context) => AppDialogDismissal(
        onClose: onClose,
        enabled: dismissible,
        child: AlertDialog(
          icon: icon,
          iconPadding: iconPadding,
          iconColor: iconColor,
          title: title,
          titlePadding: titlePadding,
          titleTextStyle: titleTextStyle,
          // Keep scrolled content and its paint effects inside the body, below
          // the fixed title and close button.
          content: content == null ? null : ClipRect(child: content!),
          contentPadding: contentPadding,
          contentTextStyle: contentTextStyle,
          actions: actions,
          actionsPadding: actionsPadding,
          actionsAlignment: actionsAlignment,
          actionsOverflowAlignment: actionsOverflowAlignment,
          actionsOverflowDirection: actionsOverflowDirection,
          actionsOverflowButtonSpacing: actionsOverflowButtonSpacing,
          buttonPadding: buttonPadding,
          backgroundColor: backgroundColor,
          elevation: elevation,
          shadowColor: shadowColor,
          surfaceTintColor: surfaceTintColor,
          semanticLabel: semanticLabel,
          insetPadding: insetPadding,
          clipBehavior: clipBehavior,
          shape: shape,
          alignment: alignment,
          constraints: constraints,
          scrollable: scrollable,
        ),
      );
}

class AppSimpleDialog extends SimpleDialog {
  AppSimpleDialog({
    super.key,
    Widget? title,
    super.titlePadding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
    super.titleTextStyle,
    super.children,
    super.contentPadding,
    super.contentTextStyle,
    super.backgroundColor,
    super.elevation = 16,
    super.shadowColor,
    super.surfaceTintColor,
    super.semanticLabel,
    super.insetPadding,
    super.clipBehavior,
    super.shape = appDialogShape,
    super.alignment,
    super.constraints,
    this.onClose,
    this.dismissible = true,
  }) : super(
          title: AppDialogHeader(
            title: title,
            onClose: onClose,
            closeEnabled: dismissible,
          ),
        );

  final VoidCallback? onClose;
  final bool dismissible;

  @override
  Widget build(BuildContext context) => AppDialogDismissal(
        onClose: onClose,
        enabled: dismissible,
        child: SimpleDialog(
          title: title,
          titlePadding: titlePadding,
          titleTextStyle: titleTextStyle,
          contentPadding: contentPadding,
          contentTextStyle: contentTextStyle,
          backgroundColor: backgroundColor,
          elevation: elevation,
          shadowColor: shadowColor,
          surfaceTintColor: surfaceTintColor,
          semanticLabel: semanticLabel,
          insetPadding: insetPadding,
          clipBehavior: clipBehavior,
          shape: shape,
          alignment: alignment,
          constraints: constraints,
          children: children,
        ),
      );
}
