import '../contract_feature.dart';
import '../contract_defaults.dart';
import 'package:intl/intl.dart';

void populateContractFeatureDefaults(
  ContractFeature feature, {
  required String? title,
  required DateTime? startTime,
  required DateTime? endTime,
  required String? description,
}) {
  // Load defaults from Occasion if empty
  if (feature.tourName == null || feature.tourName!.isEmpty) {
    feature.tourName = title;
  }

  if (feature.tourDate == null || feature.tourDate!.isEmpty) {
    final start = startTime;
    final end = endTime;
    if (start != null && end != null) {
      feature.tourDate =
          '${DateFormat.yMd().format(start)} - ${DateFormat.yMd().format(end)}';
    }
  }

  if (feature.numberOfDays == null || feature.numberOfDays!.isEmpty) {
    final start = startTime;
    final end = endTime;
    if (start != null && end != null) {
      final diffTime = end.difference(start).abs();
      // ignore: unused_local_variable
      final diffDays = diffTime.inDays +
          (diffTime.inHours % 24 > 0
              ? 1
              : 0); // Math.ceil equivalent logic or simple inDays
      // Mirror TS logic closely:
      final milliseconds =
          end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      final days = (milliseconds / (1000 * 60 * 60 * 24)).ceil();
      feature.numberOfDays = days.toString();
    }
  }

  //Regex to strip basic HTML tags for simpler matching or match around them
  if (description != null) {
    final transportRegex =
        RegExp(r'Doprava\s*(?:<\/?[^>]+>)?\s*([^.<]+)', caseSensitive: false);

    final transportMatch = transportRegex.firstMatch(description);
    if (transportMatch != null &&
        (feature.transport == null || feature.transport!.isEmpty)) {
      feature.transport = transportMatch.group(1)?.trim();
    }
  }

  if (feature.departurePoint == null || feature.departurePoint!.isEmpty) {
    feature.departurePoint = ContractDefaults.defaultDeparturePoint;
  }

  if (feature.placeOfStay == null || feature.placeOfStay!.isEmpty) {
    feature.placeOfStay = ContractDefaults.defaultPlaceOfStay;
  }

  if (feature.paymentInfo == null || feature.paymentInfo!.isEmpty) {
    feature.paymentInfo = ContractDefaults.defaultPaymentInfo;
  }
}
