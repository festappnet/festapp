import 'package:material_ui/material_ui.dart';
import '../layout_localizations.dart';

/// Optional host localization boundary for the standalone layout widgets.
///
/// The resolver receives the English source message, including formatted values.
/// Wrap editor, viewer and picker in this widget to supply product terminology.
class VenueLayoutStrings extends InheritedWidget {
  const VenueLayoutStrings({
    super.key,
    required this.resolve,
    required super.child,
  });
  final String Function(String message) resolve;
  static String text(BuildContext context, String message) =>
      context.dependOnInheritedWidgetOfExactType<VenueLayoutStrings>()?.resolve(
        message,
      ) ??
      VenueLayoutLocalizations.of(context).text(message);
  @override
  bool updateShouldNotify(VenueLayoutStrings oldWidget) =>
      resolve != oldWidget.resolve;
}

class LayoutText extends StatelessWidget {
  const LayoutText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(
    VenueLayoutStrings.text(context, data),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}
