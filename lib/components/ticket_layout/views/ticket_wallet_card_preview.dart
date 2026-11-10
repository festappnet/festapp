import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:festapp_core/time.dart';

import '../google_wallet_appearance.dart';

class TicketWalletCardPreview extends StatelessWidget {
  const TicketWalletCardPreview({
    super.key,
    required this.appearance,
    required this.occasion,
    required this.previewLabel,
    required this.sampleCodeLabel,
  });
  final GoogleWalletAppearance appearance;
  final Map<String, dynamic> occasion;
  final String previewLabel, sampleCodeLabel;
  @override
  Widget build(BuildContext context) {
    final background = appearance.backgroundColor == null
        ? const Color(0xffe8eaed)
        : Color(
            0xff000000 |
                int.parse(appearance.backgroundColor!.substring(1), radix: 16),
          );
    final foreground = background.computeLuminance() > 0.4
        ? Colors.black
        : Colors.white;
    final instant = DateTime.tryParse('${occasion['start_time'] ?? ''}');
    final start = instant == null
        ? null
        : OccasionTimeContext.named(
            (occasion['data'] as Map?)?['timezone'] as String? ??
                'Europe/Prague',
          ).toOccasionTime(instant);
    final place = (occasion['data'] as Map?)?['place_name'];
    return Semantics(
      label: previewLabel,
      child: Container(
        width: 344,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (appearance.logo != null) ...[
                          ClipOval(
                            child: Image.network(
                              appearance.logo!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 40, height: 40),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        const Flexible(child: Text('Festapp Tickets')),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${occasion['title'] ?? ''}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (start != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${DateFormat.yMMMd().format(start)} ${DateFormat.jm().format(start)}',
                      ),
                    ],
                    if (place != null) ...[
                      const SizedBox(height: 8),
                      Text('$place'),
                    ],
                    const SizedBox(height: 24),
                    Center(
                      child: QrImageView(
                        data: 'festapp-preview:WALLET-NOT-VALID',
                        size: 200,
                        padding: const EdgeInsets.all(24),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(child: Text(sampleCodeLabel)),
                  ],
                ),
              ),
              if (appearance.heroImage != null)
                AspectRatio(
                  aspectRatio: 1032 / 812,
                  child: Image.network(
                    appearance.heroImage!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
