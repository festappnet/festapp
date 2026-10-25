import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/cleaning/db_cleaning.dart';
import 'package:fstapp/components/cleaning/widgets/cleaning_report_dialog.dart';
import 'package:fstapp/components/offline/offline_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';

/// Shared "report a toilet problem" flow used by both the Cleaning page tiles
/// and the map popup: shows the report dialog and submits the chosen problem
/// via the RPC, surfacing the duplicate / rate-limit / error messages.
class CleaningReportFlow {
  /// Returns true when a report was actually submitted (or was a duplicate),
  /// so callers can refresh their status view.
  static Future<bool> report(
    BuildContext context, {
    required int placeId,
    required String placeTitle,
    VoidCallback? onShowOnMap,
  }) async {
    final result = await showDialog<CleaningReportOutcome>(
      context: context,
      builder: (_) => CleaningReportDialog(
        placeTitle: placeTitle,
        onShowOnMap: onShowOnMap,
      ),
    );
    if (result == null || !context.mounted) return false;

    try {
      final res = await DbCleaning.reportIssue(
        placeId: placeId,
        problemType: result.problemType,
        note: result.note,
      );
      if (context.mounted) {
        ToastHelper.Show(
          context,
          res.duplicate
              ? CleaningStrings.reportDuplicate
              : CleaningStrings.reportSuccess,
        );
      }
      return true;
    } on CleaningException catch (e) {
      if (context.mounted) {
        ToastHelper.Show(
          context,
          e.code == 429
              ? CleaningStrings.reportRateLimited
              : CleaningStrings.reportError,
          severity: ToastSeverity.NotOk,
        );
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        // Offline gets the unified readable message instead of the generic one.
        ToastHelper.Show(
            context,
            ExceptionHandler.isNetworkError(e)
                ? OfflineStrings.writeRequiresConnection
                : CleaningStrings.reportError,
            severity: ToastSeverity.NotOk);
      }
      return false;
    }
  }
}
