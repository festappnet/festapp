import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/images/image_url_helper.dart';

/// A circular speaker/counselor avatar. Falls back to a person icon when the
/// speaker has no image. Kept small and self-contained so it can be reused by
/// the event-page medallion and the counselor cards, and pumped directly in
/// widget tests.
class SpeakerAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;

  /// Width of the requested image transform. The default thumbnail (300px)
  /// covers small avatars; large profile photos should pass
  /// [ImageUrlHelper.mediumWidth] to stay sharp on high-DPI screens.
  final int imageWidth;

  const SpeakerAvatar(
      {super.key,
      this.imageUrl,
      this.radius = 24,
      this.imageWidth = ImageUrlHelper.thumbnailWidth});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: radius * 1.1),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      backgroundImage: CachedNetworkImageProvider(
        ImageUrlHelper.transformImageUrl(url, width: imageWidth),
      ),
    );
  }
}
