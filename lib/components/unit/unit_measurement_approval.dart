class UnitMeasurementApproval {
  final bool approved;
  final bool organizationAllowed;
  final bool runtimeSupported;
  final DateTime? requestedAt;

  const UnitMeasurementApproval({
    required this.approved,
    required this.organizationAllowed,
    required this.runtimeSupported,
    this.requestedAt,
  });

  factory UnitMeasurementApproval.fromJson(Map<String, dynamic> json) =>
      UnitMeasurementApproval(
        approved: json['approved'] == true,
        organizationAllowed: json['organization_allowed'] == true,
        runtimeSupported: json['runtime_supported'] == true,
        requestedAt: json['requested_at'] == null
            ? null
            : DateTime.parse(json['requested_at'] as String),
      );
}
