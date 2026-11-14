import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:material_ui/material_ui.dart';

import '../features/feature_constants.dart';
import '../features/feature_service.dart';
import '../features/form_feature.dart';
import '../images/image_url_helper.dart';
import '../occasion/occasion_model.dart';
import '../../database_tables/tb.dart';
import '../../services/time_helper.dart';

/// Mirrors the public web catalogue's image and separate information footer.
/// The settings preview is presentation only and never opens a reservation.
class OccasionCatalogPreview extends StatelessWidget {
  final OccasionModel occasion;

  const OccasionCatalogPreview({super.key, required this.occasion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = occasion.data?[Tb.occasions.data_image] as String?;
    final start = occasion.startTime;
    final end = occasion.endTime;
    final form = FeatureService.getFeatureDetails(
      FeatureConstants.form,
      features: occasion.features,
    );
    final price = form is FormFeature ? form.formExternalPrice : null;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerLow,
              child: image != null && image.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: ImageUrlHelper.transformImageUrl(
                        image,
                        width: ImageUrlHelper.mediumWidth,
                      ),
                      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                      fit: BoxFit.cover,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (start != null && end != null) ...[
                        Text(
                          TimeHelper.getMinimalisticDateRange(
                            context,
                            start,
                            end,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              occasion.title ?? '',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ExcludeSemantics(
                            child: Icon(
                              Icons.arrow_forward,
                              size: 20,
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (price != null && price.trim().isNotEmpty)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          price,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
