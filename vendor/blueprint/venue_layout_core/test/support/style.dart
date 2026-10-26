import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument withKindStyle(
  VenueLayoutDocument document,
  String kind,
  Map<String, dynamic> patch,
) {
  for (final entry in patch.entries) {
    document = setKindStyleLeaf(
      document,
      kind,
      [entry.key],
      value: entry.value,
      unset: entry.value == null,
    );
  }
  return document;
}
