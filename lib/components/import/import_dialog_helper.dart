// file: lib/helpers/import_dialog_helper.dart

import 'package:flutter/material.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/import_feature.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import 'csv_import_helper.dart';
import 'tickets_import_helper.dart';

enum ImportSource {
  csv,
  tickets,
}

class ImportDialogHelper {
  /// Acts as the main entry point for the user import process.
  /// It checks if the feature is enabled, shows the source selection
  /// dialog, and then calls the appropriate helper based on the user's choice.
  static Future<void> import(BuildContext context) async {
    final importFeature =
        FeatureService.getFeatureDetails(FeatureConstants.import)
            as ImportFeature?;
    if (importFeature == null || !importFeature.isEnabled) return;

    final bool canImportCsv = importFeature.importFromCsv;
    final bool canImportTickets = importFeature.importFromTickets;

    // If only one option is available, execute it directly.
    if (canImportCsv && !canImportTickets) {
      await CsvImportHelper.importFromCsv(context);
      return;
    }
    if (!canImportCsv && canImportTickets) {
      await TicketsImportHelper.importFromTickets(context);
      return;
    }

    // If both (or neither) are available, show the selection dialog.
    var choice = await showImportSourceSelectionDialog(
      context,
      showCsvImport: canImportCsv,
      showTicketImport: canImportTickets,
    );

    if (choice == null) return;

    switch (choice) {
      case ImportSource.csv:
        await CsvImportHelper.importFromCsv(context);
        break;
      case ImportSource.tickets:
        await TicketsImportHelper.importFromTickets(context);
        break;
    }
  }

  static Future<ImportSource?> showImportSourceSelectionDialog(
    BuildContext context, {
    required bool showCsvImport,
    required bool showTicketImport,
  }) async {
    List<Widget> actions = [];

    if (showCsvImport) {
      actions.add(
        DialogHelper.createDialogAction(
          FeaturesStrings.labelImportFromCsv,
          () => Navigator.of(context).pop(ImportSource.csv),
        ),
      );
    }

    if (showTicketImport) {
      actions.add(
        DialogHelper.createDialogAction(
          FeaturesStrings.importFromTicketsTitle,
          () => Navigator.of(context).pop(ImportSource.tickets),
        ),
      );
    }

    if (actions.isEmpty) {
      // No import options are enabled.
      // For now, we return null.
      return null;
    }

    return await showDialog<ImportSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(CommonStrings.import),
          content: Text(FeaturesStrings.chooseSourcePrompt),
          actions: actions,
        );
      },
    );
  }
}
