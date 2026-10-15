import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';

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
}
