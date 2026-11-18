import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// These paths refer to the source guides in automation/release/help.
enum UnitMeasurementHelp {
  basics('mereni-formularu/#zapnuti', 'form-measurement/#enable'),
  gtm('mereni-formularu/#gtm', 'form-measurement/#gtm'),
  privacy('mereni-formularu/#zasady', 'form-measurement/#privacy'),
  websites('mereni-formularu/#weby', 'form-measurement/#websites'),
  transfer('mereni-formularu/#prenos', 'form-measurement/#transfer'),
  banner('mereni-formularu/#souhlas', 'form-measurement/#consent'),
  scripts('mereni-formularu/#gtm', 'form-measurement/#gtm'),
  overview('mereni-formularu/#rezim', 'form-measurement/#mode'),
  wordpress('wordpress/#prenos-cookies', 'form-measurement/#transfer'),
  joomla('joomla/#cookie-transfer', 'form-measurement/#transfer'),
  wix('wix/#cookie-transfer', 'form-measurement/#transfer'),
  html('webnode/#cookie-transfer', 'webnode/#cookie-transfer');

  const UnitMeasurementHelp(this.cs, this.en);
  final String cs;
  final String en;

  Uri? url({
    String site = AppConfig.webLink,
    String? publishedLanguage = AppConfig.organizerHelpLanguage,
  }) {
    final path = switch (publishedLanguage) {
      'cs' => '/napoveda/$cs',
      'en' => '/help/$en',
      _ => null,
    };
    return path == null ? null : Uri.parse(site).resolve(path);
  }

  static UnitMeasurementHelp forPlatform(String platform) => switch (platform) {
    'joomla' => joomla,
    'wix' => wix,
    'html' => html,
    _ => wordpress,
  };
}

class UnitMeasurementHelpButton extends StatelessWidget {
  const UnitMeasurementHelpButton(this.topic, {required this.label, super.key});
  final UnitMeasurementHelp topic;
  final String label;

  @override
  Widget build(BuildContext context) {
    final url = topic.url();
    if (url == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: FormStrings.measurementHelpFor(label),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () => launchUrl(url),
      icon: const Icon(Icons.help_outline, size: 20),
    );
  }
}

class UnitMeasurementSectionTitle extends StatelessWidget {
  const UnitMeasurementSectionTitle(
    this.title,
    this.topic, {
    super.key,
    this.style,
  });
  final String title;
  final UnitMeasurementHelp topic;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: style)),
      UnitMeasurementHelpButton(topic, label: title),
    ],
  );
}
