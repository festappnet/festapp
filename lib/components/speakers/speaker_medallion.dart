import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/components/images/image_url_helper.dart';
import 'package:fstapp/components/speakers/speaker_avatar.dart';
import 'package:fstapp/theme_config.dart';

/// Splits a speaker's free-text subtitle ("psycholožka, terapeutka; …") into
/// individual role labels for pill rendering. Empty fragments are dropped.
List<String> splitSpeakerRoles(String? subtitle) {
  if (subtitle == null) return const [];
  return subtitle
      .split(RegExp(r'[;,]'))
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
}

/// A muted pill (subtle primary tint) — display only. Used for speaker roles
/// on the event page and counseling areas in the rozcestník so both flows
/// speak the same visual language.
class SpeakerPill extends StatelessWidget {
  final String label;

  const SpeakerPill(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// Flat (2D — no shadows, borders or elevation) centered speaker profile:
/// large circular photo, name, an optional muted detail line, a centered wrap
/// of pills and the always-visible HTML bio. Shared by the event page
/// (pills = roles split from the subtitle) and the counseling flow
/// (pills = counseling areas) so a speaker looks the same everywhere.
class SpeakerMedallion extends StatelessWidget {
  final String? imageUrl;
  final String? name;

  /// Muted centered text under the name (e.g. a counselor's detail line).
  final String? detailText;

  /// Pill labels rendered as a centered wrap under the name/detail.
  final List<String> pills;

  final String? bioHtml;
  final double photoRadius;
  final VoidCallback? onPinchStart;
  final VoidCallback? onPinchEnd;

  const SpeakerMedallion({
    super.key,
    this.imageUrl,
    this.name,
    this.detailText,
    this.pills = const [],
    this.bioHtml,
    this.photoRadius = 110,
    this.onPinchStart,
    this.onPinchEnd,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasBio = bioHtml != null && bioHtml!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SpeakerAvatar(
              imageUrl: imageUrl,
              radius: photoRadius,
              // Large profile circles need the sharper transform to stay
              // crisp on high-DPI screens.
              imageWidth: photoRadius > 75
                  ? ImageUrlHelper.mediumWidth
                  : ImageUrlHelper.thumbnailWidth),
        ),
        if (name != null && name!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(name!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                  color: ThemeConfig.darkColor(context))),
        ],
        if (detailText != null && detailText!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(detailText!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: ThemeConfig.grey700(context),
                    fontSize: 13.5,
                    height: 1.35)),
          ),
        ],
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: pills.map((p) => SpeakerPill(p)).toList(),
          ),
        ],
        if (hasBio) ...[
          const SizedBox(height: 14),
          HtmlView(
            html: bioHtml!,
            isSelectable: true,
            twoFingersOn: onPinchStart,
            twoFingersOff: onPinchEnd,
          ),
        ],
      ],
    );
  }
}
