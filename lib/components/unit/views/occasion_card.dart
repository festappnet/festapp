import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_detail_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:fstapp/components/images/image_url_helper.dart';

class OccasionCard extends StatefulWidget {
  static const double kCardBorderRadius = 15.0;
  static const double kPresentBorderWidth = 4.0;
  static const double kMinCardWidth = 300.0;
  static const double kMinCardHeight = 150.0;
  static const Duration kAnimationDuration = Duration(milliseconds: 200);

  // Back to 16:9 aspect ratio
  static const double kCardWidth = 16.0;
  static const double kCardHeight = 9.0;

  final OccasionModel occasion;
  final bool isPast;
  final bool isPresent;

  const OccasionCard({
    super.key,
    required this.occasion,
    this.isPast = false,
    this.isPresent = false,
  });

  @override
  _OccasionCardState createState() => _OccasionCardState();
}

class _OccasionCardState extends State<OccasionCard> {
  bool isHovered = false;

  // We initialize these in didChangeDependencies to avoid build-time context issues.
  bool _skipDialog = false;
  bool _hasFormFeature = false;
  bool _isDescriptionEmpty = false;
  String? _externalPrice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // This is the safest place to get translations as it's called
    // when dependencies (like EasyLocalization's BuildContext) are available.

    var details = FeatureService.getFeatureDetails(
      FeatureConstants.form,
      features: widget.occasion.features,
    );
    _externalPrice = details is FormFeature ? details.formExternalPrice : null;

    _hasFormFeature = FeatureService.isFeatureEnabled(FeatureConstants.form,
        features: widget.occasion.features);

    _isDescriptionEmpty =
        HtmlHelper.isHtmlEmptyOrNull(widget.occasion.description);

    _skipDialog = _hasFormFeature && _isDescriptionEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final Border? border = widget.isPresent
        ? Border.all(
            color: Theme.of(context).primaryColor,
            width: OccasionCard.kPresentBorderWidth,
          )
        : null;

    final double innerRadius = widget.isPresent
        ? OccasionCard.kCardBorderRadius - OccasionCard.kPresentBorderWidth
        : OccasionCard.kCardBorderRadius;

    // All logic is now handled by state variables set in didChangeDependencies.
    final String? externalPrice = _externalPrice;

    // Determines if the card interaction is enabled (previously governed button visibility)
    final bool isActionEnabled = _hasFormFeature || AppConfig.isAllUnit;
    // --- End of Logic ---

    // Card press logic (formerly Button press logic)
    void handleCardPress() async {
      // Use the state variables
      if (_skipDialog) {
        await OccasionDetailDialog.handleReserveAction(
            context, widget.occasion);
      } else if (_hasFormFeature && !_isDescriptionEmpty) {
        showDialog(
          context: context,
          builder: (context) => OccasionDetailDialog(occasion: widget.occasion),
        );
      } else if (!_hasFormFeature) {
        // Safe navigation for admins to avoid infinite loops
        if (RightsService.canEditOccasion()) {
          await RouterService.navigateToOccasionByLink(
              context, widget.occasion.link!);
        } else {
          try {
            await RightsService.updateAppData(
                link: widget.occasion.link, force: true);
          } catch (e) {
            // ignore
          }
          await RouterService.navigateOccasion(context, "");
        }
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: RepaintBoundary(
        // ← cache the entire card (including its BackdropFilters)
        child: LayoutBuilder(builder: (context, constraints) {
          // Scales kept for consistency, though button is gone
          (constraints.maxWidth / OccasionCard.kMinCardWidth).clamp(1.0, 1.5);
          (constraints.maxHeight / OccasionCard.kMinCardHeight).clamp(1.0, 1.2);

          return ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: OccasionCard.kMinCardWidth,
              minHeight: OccasionCard.kMinCardHeight,
            ),
            child: AnimatedContainer(
              duration: OccasionCard.kAnimationDuration,
              // Added transform for scale effect on hover
              transform: Matrix4.identity()..scale(isHovered ? 1.03 : 1.0),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(OccasionCard.kCardBorderRadius),
                border: border,
                boxShadow: [
                  if (widget.isPresent)
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.6),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  // Enhanced shadow effect on hover
                  BoxShadow(
                    color: isHovered ? Colors.black45 : Colors.black12,
                    blurRadius: isHovered ? 16 : 4,
                    offset: isHovered ? const Offset(0, 8) : const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(innerRadius),
                child: Stack(
                  children: [
                    // 1. Background Image
                    if (widget.occasion.data?[Tb.occasions.data_image] != null)
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: ImageUrlHelper.transformImageUrl(
                              widget.occasion.data![Tb.occasions.data_image]!,
                              width: ImageUrlHelper.mediumWidth),
                          imageRenderMethodForWeb:
                              ImageRenderMethodForWeb.HttpGet,
                          fit: BoxFit.cover,
                        ),
                      ),

                    // 2. Past Overlay
                    if (widget.isPast)
                      Positioned.fill(
                        child: Container(
                          color: Colors.grey.withOpacity(0.6),
                        ),
                      ),

                    // 3. Top overlay with cached blur (Date, Title, and Price)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: RepaintBoundary(
                        // ← cache this blurred header only
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              padding: const EdgeInsets.all(8.0),
                              color: Colors.black.withOpacity(0.4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SelectableText(
                                          TimeHelper.getMinimalisticDateRange(
                                            context,
                                            widget.occasion.startTime!,
                                            widget.occasion.endTime!,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          widget.occasion.title ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // External price badge (uses state variable)
                                  if (externalPrice != null &&
                                      externalPrice.trim().isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8.0),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: SelectableText(
                                        externalPrice,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4. Whole Card Click Area (Replaces Button)
                    // We use Positioned.fill + Material + InkWell to get the ripple effect
                    // over the image but it will sit inside the ClipRRect.
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          // Only enable tap if action is enabled (matching original button logic)
                          onTap: isActionEnabled ? handleCardPress : null,
                          splashColor: Colors.white.withOpacity(0.2),
                          highlightColor: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
