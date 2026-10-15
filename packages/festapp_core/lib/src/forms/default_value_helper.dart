import 'form_metadata.dart';

/// Read/write helpers for `form_fields.data.default_value`.
///
/// Storage shapes by field type:
///   - select_one          → String (option title)
///   - select_many         → List<String> (option titles)
///   - product_type single → String (product id)
///   - product_type multi  → List<String> (product ids)
///
/// `rename` / `remove` / `toggleInList` work polymorphically over both shapes
/// so call sites that may switch modes (product_type) don't need to branch.
class DefaultValueHelper {
  static dynamic read(Object? metadata) {
    if (metadata is! Map) return null;
    return metadata[FormMetadata.metaDefaultValue];
  }

  static String? readString(Object? metadata) {
    final v = read(metadata);
    return v is String ? v : null;
  }

  static List<String> readList(Object? metadata) {
    final v = read(metadata);
    if (v is List) return v.whereType<String>().toList();
    return const [];
  }

  static Map<String, dynamic> write(Object? metadata, dynamic value) {
    final data = Map<String, dynamic>.from((metadata ?? const {}) as Map);
    if (value == null || (value is List && value.isEmpty)) {
      data.remove(FormMetadata.metaDefaultValue);
    } else {
      data[FormMetadata.metaDefaultValue] = value;
    }
    return data;
  }

  static Object? rename(Object? metadata, String oldValue, String newValue) {
    final current = read(metadata);
    if (current is String) {
      if (current == oldValue) return write(metadata, newValue);
    } else if (current is List) {
      var changed = false;
      final next = current.map((v) {
        if (v == oldValue) {
          changed = true;
          return newValue;
        }
        return v;
      }).toList();
      if (changed) return write(metadata, next);
    }
    return metadata;
  }

  static Object? remove(Object? metadata, String value) {
    final current = read(metadata);
    if (current is String) {
      if (current == value) return write(metadata, null);
    } else if (current is List) {
      final filtered = current.where((v) => v?.toString() != value).toList();
      if (filtered.length != current.length) return write(metadata, filtered);
    }
    return metadata;
  }

  /// Toggle membership of [value] in a list-shaped default.
  /// Converts non-list current values to an empty list before toggling.
  static Map<String, dynamic> toggleInList(
    Object? metadata,
    String value,
    bool selected,
  ) {
    final next = List<String>.from(readList(metadata));
    if (selected) {
      if (!next.contains(value)) next.add(value);
    } else {
      next.remove(value);
    }
    return write(metadata, next);
  }
}
