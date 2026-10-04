import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the single data grid component and admin tabs.
/// Keys live under the "DataGrid" namespace in assets/translations/*.json.
class DataGridStrings {
  static String get refreshPending => 'DataGrid.refreshPending'.tr();
  static String get refreshData => 'DataGrid.refreshData'.tr();
  // --- SingleDataGridHeader ---
  static String get discardChanges =>
      'DataGrid.discardChanges'.tr(); // "Discard changes"
  static String get discardChangesConfirm =>
      'DataGrid.discardChangesConfirm'.tr(); // "Really discard all changes?"
  static String get savingChanges =>
      'DataGrid.savingChanges'.tr(); // "Saving changes"
  static String get downloadTable =>
      'DataGrid.downloadTable'.tr(); // "Download Table"
  static String get displayedRows =>
      'DataGrid.displayedRows'.tr(); // "Displayed rows"
  static String get items => 'DataGrid.items'.tr(); // "Items"

  // --- SingleTableDataGrid ---
  static String get noItems =>
      'DataGrid.noItems'.tr(); // "Table does not contain any items"

  // --- AdminPageHelper tab labels ---
  static String get tabInfo => 'DataGrid.tabInfo'.tr(); // "Info"
  static String get tabService => 'DataGrid.tabService'.tr(); // "Service"
  static String get tabOrders => 'DataGrid.tabOrders'.tr(); // "Orders"
  static String get tabReport => 'DataGrid.tabReport'.tr(); // "Report"
}
