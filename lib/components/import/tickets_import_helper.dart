import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/import_feature.dart';

import 'csv_import_helper.dart';
import 'import_dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class TicketsImportHelper {
  static Future<void> import(BuildContext context) async {
    final importFeature =
        FeatureService.getFeatureDetails(FeatureConstants.import)
            as ImportFeature?;
    if (importFeature == null || !importFeature.isEnabled) return;

    var choice = await ImportDialogHelper.showImportSourceSelectionDialog(
      context,
      showCsvImport: importFeature.importFromCsv,
      showTicketImport: importFeature.importFromTickets,
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

  static Future<void> importFromTickets(BuildContext context) async {
    // Show a confirmation dialog to the user before proceeding.
    var confirm = await DialogHelper.showConfirmationDialog(
        context,
        FeaturesStrings.importFromTicketsTitle,
        FeaturesStrings.importFromTicketsConfirm);

    // If the user cancels, do nothing.
    if (!confirm) return;

    try {
      // Call the database function to import users from tickets for the current occasion.
      var result = await DbUsers.importUsersFromTickets(
          RightsService.currentOccasionId()!);

      // Handle cases where the server provides no response.
      if (result == null) {
        ToastHelper.Show(context,
            "${FeaturesStrings.importFromTicketsError}: No response from server.");
        return;
      }

      // Extract the data map from the server response.
      final Map<String, dynamic> resultMap =
          result['data'] as Map<String, dynamic>;

      // Safely extract the lists of users, providing empty lists as a fallback.
      final List<dynamic> insertedUsersRaw = resultMap['inserted'] ?? [];
      final List<dynamic> updatedUsersRaw = resultMap['updated'] ?? [];
      final List<dynamic> deletedUsersRaw = resultMap['deleted'] ?? [];

      // Convert the raw dynamic lists into strongly-typed lists of maps.
      final List<Map<String, dynamic>> insertedUsers =
          insertedUsersRaw.map((e) => e as Map<String, dynamic>).toList();
      final List<Map<String, dynamic>> updatedUsers =
          updatedUsersRaw.map((e) => e as Map<String, dynamic>).toList();
      final List<Map<String, dynamic>> deletedUsers =
          deletedUsersRaw.map((e) => e as Map<String, dynamic>).toList();

      // Get the counts for each category.
      final int insertedCount = insertedUsers.length;
      final int updatedCount = updatedUsers.length;
      final int deletedCount = deletedUsers.length;

      // Format the email lists for display in the dialog.
      final insertedEmails =
          insertedUsers.map((u) => "- ${u['email']}").join("\n");
      final updatedEmails =
          updatedUsers.map((u) => "- ${u['email']}").join("\n");
      final deletedEmails =
          deletedUsers.map((u) => "- ${u['email']}").join("\n");

      // Construct the final message string to show the results.
      String message = "${FeaturesStrings.importFromTicketsCompleted}\n\n"
          "${FeaturesStrings.createdUsers} ($insertedCount):\n"
          "${insertedUsers.isEmpty ? FeaturesStrings.none : insertedEmails}\n\n"
          "${FeaturesStrings.updatedUsers} ($updatedCount):\n"
          "${updatedUsers.isEmpty ? FeaturesStrings.none : updatedEmails}\n\n"
          "${FeaturesStrings.deletedUsers} ($deletedCount):\n"
          "${deletedUsers.isEmpty ? FeaturesStrings.none : deletedEmails}";

      // Display the final summary dialog to the user.
      await DialogHelper.showConfirmationDialog(
        context,
        FeaturesStrings.importResultsTitle,
        message,
        confirmButtonMessage: CommonStrings.ok,
      );
    } catch (e) {
      // Show an error toast if any part of the process fails.
      ToastHelper.Show(
          context, "${FeaturesStrings.importFromTicketsError}: $e");
    }
  }
}
