import '../features/ticket_feature.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_form.dart';
import 'package:fstapp/components/features/feature_metadata.dart';
import 'package:fstapp/components/features/feature_service.dart';

import 'occasion_settings_strings.dart';

class OccasionFeaturesSection extends StatefulWidget {
  final List<Feature> features;
  final bool isEditingEnabled;
  final int occasionId;
  final Future<void> Function(TicketFeature)? onSaveTicket;

  const OccasionFeaturesSection({
    super.key,
    required this.features,
    required this.isEditingEnabled,
    required this.occasionId,
    this.onSaveTicket,
  });

  @override
  State<OccasionFeaturesSection> createState() =>
      _OccasionFeaturesSectionState();
}

class _OccasionFeaturesSectionState extends State<OccasionFeaturesSection> {
  String _featureSearchQuery = "";
  late TextEditingController _featureSearchController;

  @override
  void initState() {
    super.initState();
    _featureSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _featureSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredFeaturesBySearch = widget.features.where((feature) {
      final title = FeatureMetadata.getTitle(feature.code).toLowerCase();
      final description =
          FeatureMetadata.getDescription(feature.code).toLowerCase();
      final query = _featureSearchQuery.toLowerCase();
      return query.isEmpty ||
          title.contains(query) ||
          description.contains(query);
    }).toList();

    final featuresToShow = AppConfig.isAppSupported
        ? filteredFeaturesBySearch
        : filteredFeaturesBySearch
            .where((f) => !FeatureService.appSupportedFeatures.contains(f.code))
            .toList();

    final enabledFeatures = featuresToShow.where((f) => f.isEnabled).toList();
    final disabledFeatures = featuresToShow.where((f) => !f.isEnabled).toList();

    return Opacity(
      opacity: widget.isEditingEnabled ? 1.0 : 0.5,
      child: AbsorbPointer(
        absorbing: !widget.isEditingEnabled,
        child: Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(OccasionSettingsStrings.features,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              TextField(
                controller: _featureSearchController,
                enabled: widget.isEditingEnabled,
                decoration: InputDecoration(
                  labelText: OccasionSettingsStrings.searchFeatures,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon:
                      _featureSearchQuery.isNotEmpty && widget.isEditingEnabled
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _featureSearchController.clear();
                                setState(() {
                                  _featureSearchQuery = "";
                                });
                              },
                            )
                          : null,
                ),
                onChanged: (value) {
                  setState(() {
                    _featureSearchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (enabledFeatures.isNotEmpty) ...[
                Text(OccasionSettingsStrings.enabledFeatures,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...enabledFeatures.map((feature) => FeatureForm(
                    feature: feature,
                    occasion: widget.occasionId,
                    onSaveTicket: widget.onSaveTicket)),
              ],
              if (disabledFeatures.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(OccasionSettingsStrings.otherFeatures,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...disabledFeatures.map((feature) => FeatureForm(
                    feature: feature,
                    occasion: widget.occasionId,
                    onSaveTicket: widget.onSaveTicket)),
              ],
              if (featuresToShow.isEmpty && _featureSearchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(OccasionSettingsStrings.noFeaturesFound),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
