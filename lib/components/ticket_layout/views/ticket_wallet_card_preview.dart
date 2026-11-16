import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:festapp_core/time.dart';

import '../google_wallet_appearance.dart';
import '../../../app_config.dart';
import '../../../widgets/logo_widget.dart';
import '../ticket_delivery_strings.dart';

enum TicketWalletPlatform { google, apple }

/// Approximation of the native templates, using only fields issued by the
/// corresponding backend adapter. Never renders a real admission symbol.
class TicketWalletCardPreview extends StatelessWidget {
  const TicketWalletCardPreview({
    super.key,
    required this.appearance,
    required this.occasion,
    required this.previewLabel,
    required this.sampleCodeLabel,
    this.platform = TicketWalletPlatform.google,
  });
  final GoogleWalletAppearance appearance;
  final Map<String, dynamic> occasion;
  final String previewLabel, sampleCodeLabel;
  final TicketWalletPlatform platform;

  @override
  Widget build(BuildContext context) {
    final apple = platform == TicketWalletPlatform.apple;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final appleSystemFont =
        apple &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final background = appearance.backgroundColor == null
        ? (apple ? Colors.white : const Color(0xffe8eaed))
        : Color(
            0xff000000 |
                int.parse(appearance.backgroundColor!.substring(1), radix: 16),
          );
    // Apple uses this exact weighted RGB threshold in appleWalletDocument.
    final rgb = background.toARGB32();
    final bright = apple
        ? ((rgb >> 16 & 255) * .2126 +
                  (rgb >> 8 & 255) * .7152 +
                  (rgb & 255) * .0722) >
              145
        : background.computeLuminance() > .4;
    final foreground = bright ? Colors.black : Colors.white;
    final instant = DateTime.tryParse('${occasion['start_time'] ?? ''}');
    final start = instant == null
        ? null
        : OccasionTimeContext.named(
            (occasion['data'] as Map?)?['timezone'] as String? ??
                'Europe/Prague',
          ).toOccasionTime(instant);
    final place = (occasion['data'] as Map?)?['place_name'];
    final title = Text(
      '${occasion['title'] ?? ''}',
      textAlign: apple ? TextAlign.start : TextAlign.center,
      style: TextStyle(fontSize: apple ? 22 : 32, fontWeight: FontWeight.w600),
    );
    Widget inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: child,
    );
    Widget field(String label, String value, {bool alignEnd = false}) => Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 16,
            fontWeight: apple ? FontWeight.normal : FontWeight.w600,
          ),
        ),
      ],
    );
    final qr = Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(apple ? 0 : 16),
        child: QrImageView(
          data: 'festapp-preview:WALLET-NOT-VALID',
          size: apple ? 200 : 164,
          padding: const EdgeInsets.all(24),
          backgroundColor: Colors.white,
        ),
      ),
    );
    final showLogo = !appearance.logoOverridden || appearance.logo != null;
    Widget logo(double size) => appearance.logoOverridden
        ? Image.network(
            appearance.logo!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : LogoWidget(width: size, height: size, forceDark: false);
    final appleHeader = inset(
      Row(
        children: [
          if (showLogo) ...[
            SizedBox(width: 64, height: 32, child: logo(32)),
            const SizedBox(width: 12),
          ],
          // Matches issuerName / logoText in the actual Wallet documents.
          const Flexible(child: Text(AppConfig.appName)),
        ],
      ),
    );
    final googleHeader = inset(
      Column(
        children: [
          if (showLogo) ...[
            ClipOval(
              child: Container(
                color: Colors.white,
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(6),
                child: logo(64),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(AppConfig.appName, textAlign: TextAlign.center),
        ],
      ),
    );
    final card = Semantics(
      label: '$previewLabel. $sampleCodeLabel',
      child: Container(
        width: 344,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(apple ? 12 : 20),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: appleSystemFont ? 'Helvetica' : 'WalletPreviewSans',
            fontFamilyFallback: const ['WalletPreviewSans'],
            fontSize: 14,
            height: 1.25,
            color: foreground,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              apple ? appleHeader : googleHeader,
              const SizedBox(height: 20),
              if (apple) ...[
                if (appearance.heroImage != null)
                  AspectRatio(
                    key: const ValueKey('apple-wallet-strip'),
                    aspectRatio: 375 / 98,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          appearance.heroImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: LayoutBuilder(
                              builder: (context, constraints) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Akce / Event',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      Text(
                                        '${occasion['title'] ?? ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  inset(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Akce / Event',
                          style: TextStyle(fontSize: 11),
                        ),
                        title,
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                inset(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (start != null)
                        Expanded(
                          child: field(
                            'Datum / Date',
                            '${DateFormat('d. M. y').format(start)} ${DateFormat('HH:mm').format(start)}',
                          ),
                        ),
                      if (place != null && '$place'.trim().isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(child: field('Místo / Venue', '$place')),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                qr,
              ] else ...[
                inset(title),
                const SizedBox(height: 24),
                qr,
                const SizedBox(height: 20),
                if (start != null)
                  inset(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: field(
                            TicketDeliveryStrings.text('walletDate'),
                            DateFormat.yMMMd(locale).format(start),
                          ),
                        ),
                        Expanded(
                          child: field(
                            TicketDeliveryStrings.text('walletTime'),
                            DateFormat.jm(locale).format(start),
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // The adapter sends place as a text module, not class.venue.
                // It therefore appears in details, rather than under the title.
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (apple || appearance.heroImage == null) return card;
    return SizedBox(
      width: 344,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          Image.network(
            appearance.heroImage!,
            key: const ValueKey('google-wallet-hero'),
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
