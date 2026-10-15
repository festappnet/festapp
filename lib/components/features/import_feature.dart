import 'feature.dart';
import 'feature_constants.dart';

/// Feature for importing users from different sources.
class ImportFeature extends Feature {
  static const String metaImportFromCsv = "import_from_csv";
  static const String metaImportFromTickets = "import_from_tickets";

  bool importFromCsv;
  bool importFromTickets;
  bool autoImport;

  ImportFeature({
    super.code = FeatureConstants.import,
    super.isEnabled = true, // Enabled by default
    super.title,
    super.description,
    this.importFromCsv = false,
    this.importFromTickets = false,
    this.autoImport = false,
  });

  /// Creates an ImportFeature from a JSON object.
  factory ImportFeature.fromJson(Map<String, dynamic> json) {
    return ImportFeature(
      code: json[FeatureConstants.metaCode] ?? FeatureConstants.import,
      isEnabled:
          json[FeatureConstants.metaIsEnabled] ?? true, // Enabled by default
      title: json[FeatureConstants.metaTitle],
      description: json[FeatureConstants.metaDescription],
      importFromCsv: json[metaImportFromCsv] ?? false,
      importFromTickets: json[metaImportFromTickets] ?? false,
      autoImport: json[FeatureConstants.importAutoImport] ?? false,
    );
  }

  /// Converts the feature to a JSON object.
  @override
  Map<String, dynamic> toJson() {
    return {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      metaImportFromCsv: importFromCsv,
      metaImportFromTickets: importFromTickets,
      FeatureConstants.importAutoImport: autoImport,
    };
  }

  /// Builds the form field widget for this feature.
}

/// A stateful widget to manage the form's UI state for the ImportFeature.
