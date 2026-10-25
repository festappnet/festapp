import 'package:fstapp/widgets/app_dialog.dart';
import 'package:material_ui/material_ui.dart';

class StandardDialog extends StatelessWidget {
  final Widget content;
  final Widget? title;
  final double maxWidth;
  final VoidCallback? onClose;

  const StandardDialog({
    super.key,
    required this.content,
    this.title,
    this.maxWidth = 600,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      onClose: onClose,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, minHeight: 120),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDialogHeader(title: title, onClose: onClose),
              Flexible(child: content),
            ],
          ),
        ),
      ),
    );
  }
}
