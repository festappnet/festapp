import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/contract_defaults.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:intl/intl.dart';

class ContractFeature extends Feature {
  String? transport;
  String? departurePoint;
  String? placeOfStay;
  String? tourName;
  String? tourDate;
  String? notes;
  String? numberOfDays;
  String? paymentInfo;

  ContractFeature({
    required super.code,
    super.isEnabled,
    this.transport,
    this.departurePoint,
    this.placeOfStay,
    this.tourName,
    this.tourDate,
    this.notes,
    this.numberOfDays,
    this.paymentInfo,
  });

  factory ContractFeature.fromJson(Map<String, dynamic> json) {
    return ContractFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      transport: json[FeatureConstants.contractTransport],
      departurePoint: json[FeatureConstants.contractDeparturePoint],
      placeOfStay: json[FeatureConstants.contractPlaceOfStay],
      tourName: json[FeatureConstants.contractTourName],
      tourDate: json[FeatureConstants.contractTourDate],
      notes: json[FeatureConstants.contractNotes],
      numberOfDays: json[FeatureConstants.contractNumberOfDays],
      paymentInfo: json[FeatureConstants.contractPaymentInfo],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
    };
    if (transport != null)
      data[FeatureConstants.contractTransport] = transport!;
    if (departurePoint != null)
      data[FeatureConstants.contractDeparturePoint] = departurePoint!;
    if (placeOfStay != null)
      data[FeatureConstants.contractPlaceOfStay] = placeOfStay!;
    if (tourName != null) data[FeatureConstants.contractTourName] = tourName!;
    if (tourDate != null) data[FeatureConstants.contractTourDate] = tourDate!;
    if (notes != null) data[FeatureConstants.contractNotes] = notes!;
    if (numberOfDays != null)
      data[FeatureConstants.contractNumberOfDays] = numberOfDays!;
    if (paymentInfo != null)
      data[FeatureConstants.contractPaymentInfo] = paymentInfo!;
    return data;
  }

  void loadFromDescription() {
    final occasion = RightsService.currentOccasion();
    if (occasion == null) return;

    // Load defaults from Occasion if empty
    if (tourName == null || tourName!.isEmpty) {
      tourName = occasion.title;
    }

    if (tourDate == null || tourDate!.isEmpty) {
      final start = occasion.startTime;
      final end = occasion.endTime;
      if (start != null && end != null) {
        tourDate =
            '${DateFormat('d. M. yyyy').format(start)} - ${DateFormat('d. M. yyyy').format(end)}';
      }
    }

    if (numberOfDays == null || numberOfDays!.isEmpty) {
      final start = occasion.startTime;
      final end = occasion.endTime;
      if (start != null && end != null) {
        final diffTime = end.difference(start).abs();
        final diffDays = diffTime.inDays +
            (diffTime.inHours % 24 > 0
                ? 1
                : 0); // Math.ceil equivalent logic or simple inDays
        // Mirror TS logic closely:
        final milliseconds =
            end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
        final days = (milliseconds / (1000 * 60 * 60 * 24)).ceil();
        numberOfDays = days.toString();
      }
    }

    final description = occasion.description;

    //Regex to strip basic HTML tags for simpler matching or match around them
    if (description != null) {
      final transportRegex =
          RegExp(r'Doprava\s*(?:<\/?[^>]+>)?\s*([^.<]+)', caseSensitive: false);

      final transportMatch = transportRegex.firstMatch(description);
      if (transportMatch != null && (transport == null || transport!.isEmpty)) {
        transport = transportMatch.group(1)?.trim();
      }
    }

    if (departurePoint == null || departurePoint!.isEmpty) {
      departurePoint = ContractDefaults.defaultDeparturePoint;
    }

    if (placeOfStay == null || placeOfStay!.isEmpty) {
      placeOfStay = ContractDefaults.defaultPlaceOfStay;
    }

    if (paymentInfo == null || paymentInfo!.isEmpty) {
      paymentInfo = ContractDefaults.defaultPaymentInfo;
    }
  }

  @override
  Widget buildFormField(BuildContext context) {
    if (isEnabled && (transport == null && departurePoint == null)) {
      loadFromDescription();
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
                loadFromDescription();
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
