import 'model.dart';

/// Physical seating rules, independent of colors and material families.
class TableSeating {
  const TableSeating({
    this.width = 40,
    this.height = 40,
    this.gap = 12,
    this.spacing = 12,
    this.edgePadding = 12,
  });
  final double width, height, gap, spacing, edgePadding;
  double get pitch => width + spacing;
  double get offset => height / 2 + gap;
  TableSeating withGap(double value) => copyWith(gap: value);
  TableSeating copyWith({
    double? width,
    double? height,
    double? gap,
    double? spacing,
    double? edgePadding,
  }) => TableSeating(
    width: width ?? this.width,
    height: height ?? this.height,
    gap: gap ?? this.gap,
    spacing: spacing ?? this.spacing,
    edgePadding: edgePadding ?? this.edgePadding,
  );
  factory TableSeating.fromTable(LayoutNode table) =>
      TableSeating.fromRecord(table.seating);
  factory TableSeating.fromRecord(Map<String, dynamic> value) => TableSeating(
    width: (value['width'] as num? ?? 40).toDouble(),
    height: (value['height'] as num? ?? 40).toDouble(),
    gap: (value['gap'] as num? ?? 12).toDouble(),
    spacing: (value['spacing'] as num? ?? 12).toDouble(),
    edgePadding: (value['edgePadding'] as num? ?? 12).toDouble(),
  );
  Map<String, dynamic> get record => {
    'width': width,
    'height': height,
    'gap': gap,
    'spacing': spacing,
    'edgePadding': edgePadding,
  };
  factory TableSeating.fromDocument(
    VenueLayoutDocument doc,
    LayoutNode table, {
    String? excludeSeatId,
  }) {
    return TableSeating.fromRecord({...doc.seatingDefaults, ...table.seating});
  }
}

/// Palette chairs match the prevailing physical size in the current document.
TableSeating documentSeating(VenueLayoutDocument doc) {
  return TableSeating.fromRecord(doc.seatingDefaults);
}
