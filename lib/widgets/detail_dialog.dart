import 'package:flutter/material.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/components/images/zoomable_image/zoomable_image.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class DetailDialog extends StatefulWidget {
  final String title;
  final String? htmlDescription;
  final bool canEdit;
  final VoidCallback? onEditPressed;
  final Widget? customContentWidget;
  final List<Widget> titleActions;
  final bool shrinkWrapCustomContent;

  const DetailDialog({
    super.key,
    required this.title,
    this.htmlDescription,
    this.canEdit = false,
    this.onEditPressed,
    this.customContentWidget,
    this.titleActions = const [],
    this.shrinkWrapCustomContent = false,
  });

  @override
  State<DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<DetailDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.title,
            ),
          ),
          ...widget.titleActions,
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: StylesConfig.formMaxWidthMid, maxHeight: 500),
        child: SizedBox(
          height: widget.customContentWidget != null &&
                  !widget.shrinkWrapCustomContent
              ? 500
              : null,
          width: widget.customContentWidget != null
              ? StylesConfig.formMaxWidthMid
              : null,
          child: PinchScrollView(
            builder: (onPinchStart, onPinchEnd) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.canEdit && widget.onEditPressed != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextButton.icon(
                      onPressed: _handleEditPressed,
                      icon: const Icon(Icons.edit),
                      label: Text(CommonStrings.edit),
                    ),
                  ),
                if (widget.customContentWidget != null) ...[
                  const SizedBox(height: 16),
                  widget.customContentWidget!,
                ],
                if (widget.htmlDescription != null)
                  HtmlView(
                    html: widget.htmlDescription!,
                    isSelectable: true,
                    twoFingersOn: onPinchStart,
                    twoFingersOff: onPinchEnd,
                  ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        TextButton(
          child: Text(CommonStrings.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _handleEditPressed() {
    if (widget.onEditPressed != null) {
      Navigator.of(context).pop();
      widget.onEditPressed!();
    }
  }
}
