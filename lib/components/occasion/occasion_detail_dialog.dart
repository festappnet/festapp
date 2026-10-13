import 'package:flutter/material.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/forms/views/form_page.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class OccasionDetailDialog extends StatelessWidget {
  final OccasionModel occasion;

  const OccasionDetailDialog({super.key, required this.occasion});

  /// Unified reserve button logic, usable from anywhere.
  static Future<void> handleReserveAction(
      BuildContext context, OccasionModel occasion) async {
    var details = FeatureService.getFeatureDetails(
      FeatureConstants.form,
      features: occasion.features,
    );
    if (details is FormFeature) {
      if (details.formUseExternal == true) {
        final externalUrl = details.formExternalLink;
        if (externalUrl != null && externalUrl.isNotEmpty) {
          await LaunchUrlService.openExternalUrl(externalUrl);
          return;
        }
      }
    }
    // Fallback to internal form page navigation.
    RouterService.navigate(
      context,
      "${FormPage.ROUTE}/${occasion.form!.link!}",
    );
  }

  /// Unified reserve button logic.
  void _onReservePressed(BuildContext context) async {
    await OccasionDetailDialog.handleReserveAction(context, occasion);
  }

  @override
  Widget build(BuildContext context) {
    final formDetails = FeatureService.getFeatureDetails(
      FeatureConstants.form,
      features: occasion.features,
    );
    final reserveTitle = formDetails is FormFeature
        ? formDetails.reserveButtonTitle ?? CommonStrings.reserveASpot
        : CommonStrings.reserveASpot;
    final unifiedButtonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16),
      side: BorderSide(
        color: ThemeConfig.blackColor(context),
        width: 1.0,
      ),
      minimumSize: const Size.fromHeight(50),
    );

    return Dialog(
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidthMid),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32), // Space for close button
                    SelectableText(
                      occasion.title ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      TimeHelper.getMinimalisticDateRange(
                        context,
                        occasion.startTime!,
                        occasion.endTime!,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: HtmlView(
                        html: occasion.description ?? '',
                        isSelectable: true,
                      ),
                    ),
                    const SizedBox(height: 24),

                    OutlinedButton(
                      onPressed: () => _onReservePressed(context),
                      style: unifiedButtonStyle,
                      child: Text(
                        reserveTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 24,
                    color: ThemeConfig.blackColor(context).withOpacity(0.8),
                  ),
                  splashRadius: 20,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: CommonStrings.close,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
