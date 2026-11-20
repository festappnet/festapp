import 'unit_measurement_approval.dart';

class MetaCapiApproval {
  final bool approved;
  final bool canRequest;
  final MeasurementRequestState requestState;
  final DateTime? requestedAt;

  const MetaCapiApproval({
    required this.approved,
    required this.canRequest,
    required this.requestState,
    this.requestedAt,
  });

  factory MetaCapiApproval.fromJson(Map<String, dynamic> json) {
    final state = MeasurementRequestState.fromJson(json['request_state']);
    return MetaCapiApproval(
      approved: json['approved'] == true,
      canRequest:
          json['can_request'] == true &&
          (state == MeasurementRequestState.notRequested ||
              state == MeasurementRequestState.retryAvailable),
      requestState: state,
      requestedAt: DateTime.tryParse(json['requested_at']?.toString() ?? ''),
    );
  }
}
