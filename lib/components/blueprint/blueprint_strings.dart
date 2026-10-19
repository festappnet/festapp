import 'package:easy_localization/easy_localization.dart';

class BlueprintStrings {
  // --- BlueprintTab (General) ---
  static String get changeTitle =>
      'FeatureBlueprint.changeTitle'.tr(); // "Change title"

  // --- Left Panel (Legend) ---
  static String get legendInstruction => 'FeatureBlueprint.legendInstruction'
      .tr(); // "Click an option in the legend to add seats."
  static String get legendBlackArea =>
      'FeatureBlueprint.legendBlackArea'.tr(); // "Black area"
  static String get legendAvailable =>
      'FeatureBlueprint.legendAvailable'.tr(); // "Available"
  static String get legendEmpty =>
      'FeatureBlueprint.legendEmpty'.tr(); // "Empty"
  static String get legendUsed => 'FeatureBlueprint.legendUsed'.tr(); // "Used"
  static String get legendOccupied =>
      'FeatureBlueprint.legendOccupied'.tr(); // "Occupied"
  static String get legendSelected =>
      'FeatureBlueprint.legendSelected'.tr(); // "Selected"
  static String get legendSwapSeats =>
      'FeatureBlueprint.legendSwapSeats'.tr(); // "Swap Seats"

  // --- Main Content (Dimension & Background Controls) ---
  static String get width => 'FeatureBlueprint.width'.tr(); // "Width"
  static String get height => 'FeatureBlueprint.height'.tr(); // "Height"
  static String get background =>
      'FeatureBlueprint.background'.tr(); // "Background"
  static String get changeBackground =>
      'FeatureBlueprint.changeBackground'.tr(); // "Change background"
  static String get uploadSVG =>
      'FeatureBlueprint.uploadSVG'.tr(); // "Upload SVG"
  static String get uploadImage =>
      'FeatureBlueprint.uploadImage'.tr(); // "Upload Image (PNG recommended)"
  static String get removeBackground =>
      'FeatureBlueprint.removeBackground'.tr(); // "Remove background"

  // --- Right Panel (Groups) ---
  static String get groupsTitle =>
      'FeatureBlueprint.groupsTitle'.tr(); // "Groups (Tables):"
  static String get assignProductToGroup =>
      'FeatureBlueprint.assignProductToGroup'.tr(); // "Assign product to group"
  static String get noProductAssigned =>
      'FeatureBlueprint.noProductAssigned'.tr(); // "No Product Assigned"

  // --- Dialogs ---
  static String get dialogGroupNumber =>
      'FeatureBlueprint.dialogGroupNumber'.tr(); // "Group number"
  static String get dialogTitle =>
      'FeatureBlueprint.dialogTitle'.tr(); // "Title"
  static String get dialogImportSvgTitle =>
      'FeatureBlueprint.dialogImportSvgTitle'.tr(); // "Import SVG background"
  static String get dialogImportImageTitle =>
      'FeatureBlueprint.dialogImportImageTitle'
          .tr(); // "Import image background"
  static String get dialogConfirmRemoveBackgroundTitle =>
      'FeatureBlueprint.dialogConfirmRemoveBackgroundTitle'
          .tr(); // "Remove background"
  static String get dialogConfirmRemoveBackgroundContent =>
      'FeatureBlueprint.dialogConfirmRemoveBackgroundContent'
          .tr(); // "Are you sure you want to remove the background?"

  // --- Toasts & Messages ---
  static String get toastOccupiedCannotBeChanged =>
      'FeatureBlueprint.toastOccupiedCannotBeChanged'
          .tr(); // "Places that are occupied cannot be changed."
  static String get toastSelectGroupFirst =>
      'FeatureBlueprint.toastSelectGroupFirst'
          .tr(); // "First, select or create a group to add a spot (on the right)."
  static String get toastSpotAdded =>
      'FeatureBlueprint.toastSpotAdded'.tr(); // "Spot added:"
  static String get toastAreaRemoved =>
      'FeatureBlueprint.toastAreaRemoved'.tr(); // "Area removed."
  static String get toastSpotRemoved =>
      'FeatureBlueprint.toastSpotRemoved'.tr(); // "Spot removed."
  static String get toastInvalidSvg => 'FeatureBlueprint.toastInvalidSvg'
      .tr(); // "The selected file is not a valid SVG."
  static String get toastSvgUploadSuccess =>
      'FeatureBlueprint.toastSvgUploadSuccess'
          .tr(); // "SVG background uploaded successfully."
  static String get toastSvgReadFail =>
      'FeatureBlueprint.toastSvgReadFail'.tr(); // "Failed to read SVG file."
  static String get toastImageUploadSuccess =>
      'FeatureBlueprint.toastImageUploadSuccess'
          .tr(); // "Image background uploaded successfully."
  static String get toastImageUploadFail =>
      'FeatureBlueprint.toastImageUploadFail'.tr(); // "Failed to upload image."
  static String get toastBackgroundRemoved =>
      'FeatureBlueprint.toastBackgroundRemoved'.tr(); // "Background removed."
  static String get toastMaxTicketsReached =>
      'FeatureBlueprint.toastMaxTicketsReached'
          .tr(); // "It is not possible to select more tickets."

  // --- Swap Seats Feature ---
  static String get swapHelpIntro => 'FeatureBlueprint.swapHelpIntro'
      .tr(); // "SWAP MODE: Select two seats to exchange their orders."
  static String get swapHelpSelectFirst =>
      'FeatureBlueprint.swapHelpSelectFirst'
          .tr(); // "Select the first seat to swap."
  static String swapHelpSelectSecond(String seatName) =>
      'FeatureBlueprint.swapHelpSelectSecond'.tr(namedArgs: {
        'seatName': seatName
      }); // "Seat {seatName} selected. Select the second seat to swap."
  static String get swapConfirmTitle =>
      'FeatureBlueprint.swapConfirmTitle'.tr(); // "Confirm Seat Swap"
  static String swapConfirmMessage(
          String summary1, String seat1, String summary2, String seat2) =>
      'FeatureBlueprint.swapConfirmMessage'
          .tr(); // "Are you sure you want to swap these seats?"
  static String get swapErrorEmpty => 'FeatureBlueprint.swapErrorEmpty'
      .tr(); // "Cannot swap empty or blocked areas."
  static String get swapSuccess =>
      'FeatureBlueprint.swapSuccess'.tr(); // "Seats swapped successfully."

  // --- Swap Summary Strings (used in BlueprintObjectModel) ---
  static String swapSummaryCustomer(String ticketSymbol, String customerName) =>
      'FeatureBlueprint.swapSummaryCustomer'.tr(namedArgs: {
        'ticketSymbol': ticketSymbol,
        'customerName': customerName
      }); // "Order: {ticketSymbol} ({customerName})"
  static String get swapSummaryOccupied =>
      'FeatureBlueprint.swapSummaryOccupied'.tr(); // "Occupied Seat"
  static String get swapSummaryAvailable =>
      'FeatureBlueprint.swapSummaryAvailable'.tr(); // "Available Seat"
  static String get swapSummaryBlack =>
      'FeatureBlueprint.swapSummaryBlack'.tr(); // "Blocked Area"
  static String get swapSummaryUsed =>
      'FeatureBlueprint.swapSummaryUsed'.tr(); // "Used Seat"
  static String get swapSummarySelected =>
      'FeatureBlueprint.swapSummarySelected'.tr(); // "Selected Seat"
  static String get swapSummaryEmpty =>
      'FeatureBlueprint.swapSummaryEmpty'.tr(); // "Empty Area"

  // --- Object Model (New) ---
  static String objectModelToString(String groupTitle, String seatTitle) =>
      'FeatureBlueprint.objectModelToString'.tr(namedArgs: {
        'groupTitle': groupTitle,
        'seatTitle': seatTitle
      }); // "Table {groupTitle}, Seat {seatTitle}"

  // --- Product Management (New) ---
  static String get editProduct =>
      'FeatureBlueprint.editProduct'.tr(); // "Edit Product"
  static String get createProduct =>
      'FeatureBlueprint.createProduct'.tr(); // "Create New Product"
  static String get selectProduct =>
      'FeatureBlueprint.selectProduct'.tr(); // "Select Product"
  static String get noSpotProducts => 'FeatureBlueprint.noSpotProducts'
      .tr(); // "No spot products are defined. You can create them in the product manager."
  static String get productAssigned => 'FeatureBlueprint.productAssigned'
      .tr(); // "Product assigned to all spots in the group."
  static String get productCreated =>
      'FeatureBlueprint.productCreated'.tr(); // "Product created."
  static String get productUpdated =>
      'FeatureBlueprint.productUpdated'.tr(); // "Product updated."

  // --- Create New Order Feature ---
  static String get legendCreateOrder =>
      'FeatureBlueprint.legendCreateOrder'.tr(); // "Create Order"
  static String get createOrderHelp => 'FeatureBlueprint.createOrderHelp'
      .tr(); // "Select seats to create a new order."
  static String get btnCreateOrder =>
      'FeatureBlueprint.btnCreateOrder'.tr(); // "Create Order"
  static String get confirmOrder =>
      'FeatureBlueprint.confirmOrder'.tr(); // "Confirm Order"
  static String get orderCreatedSuccess =>
      'FeatureBlueprint.orderCreatedSuccess'
          .tr(); // "Order created successfully."

// --- Group/Product Manager Dialog ---
  static String get manageGroupProducts =>
      'FeatureBlueprint.manageGroupProducts'.tr(); // "Manage Group Products"
  static String get groupDefaultProduct =>
      'FeatureBlueprint.groupDefaultProduct'.tr(); // "Group Product"
  static String get individualSeats =>
      'FeatureBlueprint.individualSeats'.tr(); // "Individual Seats"
  static String get customizeIndividualSeats =>
      'FeatureBlueprint.customizeIndividualSeats'
          .tr(); // "Customize individual seats"
  static String get occupiedWarningInline =>
      'FeatureBlueprint.occupiedWarningInline'
          .tr(); // "Note: Changing products here will NOT update prices for seats that are already ordered."
  static String get customProductLabel =>
      'FeatureBlueprint.customProductLabel'.tr(); // "Custom"
  static String get productAssignedToAll =>
      'FeatureBlueprint.productAssignedToAll'
          .tr(); // "Product assigned to all seats."

  // Status descriptions
  static String get statusUniform =>
      'FeatureBlueprint.statusUniform'.tr(); // "Applied to all seats"
  static String get statusMixed =>
      'FeatureBlueprint.statusMixed'.tr(); // "Mixed products"
  static String get currentProductPrefix =>
      'FeatureBlueprint.currentProductPrefix'.tr(); // "Current: "
  static String get mixedProducts =>
      'FeatureBlueprint.mixedProducts'.tr(); // "Mixed / Various"
  static String get toastNoTemplateProduct =>
      'FeatureBlueprint.toastNoTemplateProduct'
          .tr(); // "Cannot create product..."
  static String get uniformViewHelp => 'FeatureBlueprint.uniformViewHelp'
      .tr(); // "All seats share the same product..."
  static String get warningNoCancellationEmail =>
      'FeatureBlueprint.warningNoCancellationEmail'
          .tr(); // "Note: Users will NOT receive cancellation emails for these changes."
}
