import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import '../contract_feature.dart';
import 'contract_feature_defaults.dart';

extension ContractFeatureSettingsEditor on ContractFeature {
  void _populateDefaults() {
    final occasion = RightsService.currentOccasion();
    if (occasion == null) return;
    populateContractFeatureDefaults(this,
        title: occasion.title,
        startTime: occasion.startTime,
        endTime: occasion.endTime,
        description: occasion.description);
  }

  Widget buildSettingsEditor(BuildContext context) {
    if (isEnabled && (transport == null && departurePoint == null)) {
      _populateDefaults();
    }
    return StatefulBuilder(builder: (ctx, updateLocal) {
      void setLocal(VoidCallback change) {
        updateLocal(change);
        EditorDraftScope.changed(ctx);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _populateDefaults();
                setLocal(() {});
              },
              icon: const Icon(Icons.copy),
              label: Text(FeaturesStrings.contractLoadFromDescription),
            ),
          ),
          TextFormField(
            key: ValueKey('tourName_$tourName'),
            initialValue: tourName,
            decoration:
                InputDecoration(labelText: FeaturesStrings.contractTourName),
            onChanged: (val) => tourName = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('numberOfDays_$numberOfDays'),
            initialValue: numberOfDays,
            decoration: InputDecoration(
                labelText: FeaturesStrings.contractNumberOfDays),
            onChanged: (val) => numberOfDays = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('tourDate_$tourDate'),
            initialValue: tourDate,
            decoration:
                InputDecoration(labelText: FeaturesStrings.contractTourDate),
            onChanged: (val) => tourDate = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('transport_$transport'),
            initialValue: transport,
            decoration:
                InputDecoration(labelText: FeaturesStrings.contractTransport),
            onChanged: (val) => transport = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('departurePoint_$departurePoint'),
            initialValue: departurePoint,
            decoration: InputDecoration(
                labelText: FeaturesStrings.contractDeparturePoint),
            onChanged: (val) => departurePoint = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('placeOfStay_$placeOfStay'),
            initialValue: placeOfStay,
            decoration:
                InputDecoration(labelText: FeaturesStrings.contractPlaceOfStay),
            onChanged: (val) => placeOfStay = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: notes,
            decoration:
                InputDecoration(labelText: FeaturesStrings.contractNotes),
            onChanged: (val) => notes = val,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('paymentInfo_$paymentInfo'),
            initialValue: paymentInfo,
            maxLines: 3,
            decoration:
                InputDecoration(labelText: FeaturesStrings.contractPaymentInfo),
            onChanged: (val) => paymentInfo = val,
          ),
        ],
      );
    });
  }
}
