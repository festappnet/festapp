import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/components/html/html_view.dart';

class DescriptionTooltip extends StatelessWidget {
  final String description;
  final Widget child;

  const DescriptionTooltip({
    super.key,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (HtmlHelper.isHtmlEmptyOrNull(description)) {
      return child;
    }

    final tooltipTheme = TooltipTheme.of(context);
    final effectiveDecoration = tooltipTheme.decoration ??
        BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[700]
              : Colors.white,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          border: Border.all(color: Colors.grey.shade400, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        );
    final baseTextStyle =
        tooltipTheme.textStyle ?? DefaultTextStyle.of(context).style;
    final effectiveTextStyle = baseTextStyle.copyWith(fontSize: 14);

    return Tooltip(
      showDuration: const Duration(seconds: 15),
      preferBelow: true,
      verticalOffset: 20, // Adjusted offset
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(color: Colors.transparent),
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: Container(
          padding: const EdgeInsets.all(10.0),
          constraints: const BoxConstraints(
              maxWidth: 300,
              maxHeight: 200), // Slightly smaller constraints for form look
          decoration: effectiveDecoration,
          child: SingleChildScrollView(
            child: HtmlView(
              html: description,
              fontSize: effectiveTextStyle.fontSize!,
              color: effectiveTextStyle.color,
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}
