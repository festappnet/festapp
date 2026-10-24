class UnitLegalProfile {
  final int unitId, revision;
  final String status;
  final Map<String, dynamic> details;
  final String? feedback, note, source, submittedAt, verifiedAt;
  UnitLegalProfile.fromJson(Map<String, dynamic> json)
      : unitId = json['unitId'] as int,
        revision = json['revision'] as int,
        status = json['status'] as String,
        details = Map.unmodifiable({
          for (final key in fields)
            key: key == 'address'
                ? Map<String, dynamic>.unmodifiable(
                    Map<String, dynamic>.from(json[key] as Map? ?? {}))
                : json[key]
        }),
        feedback = json['feedbackToApplicant'] as String?,
        note = json['reviewNote'] as String?,
        source = json['reviewSource'] as String?,
        submittedAt = json['submittedAt'] as String?,
        verifiedAt = json['verifiedAt'] as String?;
  static const fields = [
    'legalName',
    'countryCode',
    'registrationNumber',
    'vatId',
    'address',
    'contactEmail',
    'phone',
    'website'
  ];
  bool get complete =>
      ['legalName', 'countryCode', 'registrationNumber', 'contactEmail']
          .every((k) => (details[k] as String? ?? '').trim().isNotEmpty) &&
      ['street', 'city', 'postalCode'].every((k) =>
          ((details['address'] as Map)[k] as String? ?? '').trim().isNotEmpty);
}

class VerificationResult {
  final int code;
  final UnitLegalProfile? profile;
  final Map<String, String> fieldErrors;
  VerificationResult.fromJson(Map<String, dynamic> json)
      : code = json['code'] as int,
        profile = json['profile'] is Map
            ? UnitLegalProfile.fromJson(
                Map<String, dynamic>.from(json['profile']))
            : null,
        fieldErrors =
            Map<String, String>.from(json['fieldErrors'] as Map? ?? {});
}
