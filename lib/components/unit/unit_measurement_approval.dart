class UnitMeasurementApproval {
  final bool approved;
  final bool organizationAllowed;
  final bool runtimeSupported;
  final DateTime? requestedAt;
  final List<String> approvedOrigins;
  final List<String> requestedOrigins;

  const UnitMeasurementApproval({
    required this.approved,
    required this.organizationAllowed,
    required this.runtimeSupported,
    this.requestedAt,
    this.approvedOrigins = const [],
    this.requestedOrigins = const [],
  });

  factory UnitMeasurementApproval.fromJson(Map<String, dynamic> json) =>
      UnitMeasurementApproval(
        approvedOrigins: List<String>.from(json['approved_origins'] ?? const []),
        requestedOrigins: List<String>.from(json['requested_origins'] ?? const []),
        approved: json['approved'] == true,
        organizationAllowed: json['organization_allowed'] == true,
        runtimeSupported: json['runtime_supported'] == true,
        requestedAt: json['requested_at'] == null
            ? null
            : DateTime.parse(json['requested_at'] as String),
      );
}
