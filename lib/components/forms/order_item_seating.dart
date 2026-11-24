import 'order_overview_strings.dart';

String? orderItemSeatingText(Map item) {
  final standing = item['isStanding'] == true;
  final placement = item['placement'];
  final raw = standing ? item['standingAreaTitle'] : item['spotGroupTitle'];
  final labelKey = placement is Map ? placement['labelKey'] as String? : null;
  final value = placement is Map ? placement['value'] : raw;
  final separator = placement is Map ? placement['separator'] as String? : null;
  final group = [
    if (labelKey != null) OrderOverviewStrings.text(labelKey),
    if (value != null && value.toString().trim().isNotEmpty) value.toString(),
  ].join(separator ?? ' ');
  final seat = standing ? '' : item['spotTitle']?.toString().trim() ?? '';
  final parts = [
    if (group.isNotEmpty) group,
    if (seat.isNotEmpty) '${OrderOverviewStrings.text('seat')}: $seat',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
