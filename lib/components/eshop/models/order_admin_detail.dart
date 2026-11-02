import 'package:festapp_core/forms.dart';

import 'order_model.dart';

Map<String, dynamic> detailMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> detailRows(dynamic value) =>
    (value as List? ?? const []).map(detailMap).toList();

/// Admin read contract: snapshots, live identities and geometry stay separate.
class OrderAdminDetail {
  OrderAdminDetail(this.json);
  final Map<String, dynamic> json;
  Map<String, dynamic> get order => detailMap(json['order']);
  OrderModel get model => OrderModel.fromJson({
    ...order,
    if (json['waitlistSummary'] != null)
      'waitlistSummary': json['waitlistSummary'],
  });
  Map<String, dynamic> get payment => detailMap(json['payment']);
  Map<String, dynamic> get emailSummary => detailMap(json['emailSummary']);
  List<Map<String, dynamic>> get tickets => detailRows(json['tickets']);
  List<Map<String, dynamic>> get places => detailRows(json['places']);
  List<Map<String, dynamic>> get plans => detailRows(json['plans']);
  List<FormFieldDefinition> get fields =>
      detailRows(json['fields']).map(FormFieldDefinition.fromJson).toList();
  String get placementFingerprint => json['placementFingerprint'] as String;
  bool get canWrite => json['capabilities']?['write'] == true;
}
