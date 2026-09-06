import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/scan/scan_strings.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';

import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/vibrate_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/feature.dart';

import 'scan_field_mappings.dart';
import 'scan_result_display.dart';
import 'ticket_search_dialog.dart';
import 'user_search_dialog.dart';

enum ScanState { valid, invalid, used, nothing, ordered, notFound }

@RoutePage()
class ScanPage extends StatefulWidget {
  static const ROUTE = "scan";

  String? scanCode;
  ScanPage({@pathParam this.scanCode, super.key});

  @override
  _ScanPageState createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  static const String _defaultResetPassword = "1";

  TicketModel? _scannedObject;
  ScanState _scanState = ScanState.nothing;

  // To prevent multiple scans
  String? rightNowScanned;
  bool _showHelpText = true;
  String? _occasionTitle;
  List<Feature> _features = [];
  bool _canScanTicketsManually = false;

  // Track if we just successfully used the ticket
  bool _justConfirmed = false;

  @override
  void initState() {
    super.initState();
    final ticketFeature =
        FeatureService.getFeatureDetails(FeatureConstants.ticket)
            as TicketFeature?;
    if (ticketFeature?.canScanManually == true) {
      _canScanTicketsManually = true;
    }
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showHelpText = false;
        });
      }
    });
  }

  final MobileScannerController _mobileScannerController =
      MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _mobileScannerController.dispose();
    super.dispose();
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    if (widget.scanCode == null && context.routeData.hasPendingChildren) {
      widget.scanCode =
          context.routeData.pendingChildren[0].params.getString("scanCode");
    }

    if (kIsWeb) {
      MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
          "https://unpkg.com/@zxing/library@0.21.3");
    }
    AppLogger.debug(widget.scanCode ?? '');

    checkForCode();
  }

  Future<void> checkForCode() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (widget.scanCode == null) {
      String? inputScanCode = await DialogHelper.showInputDialog(
        context: context,
        dialogTitle: ScanStrings.enterScanCode,
        labelText: ScanStrings.scanCode,
      );
      if (inputScanCode != null && inputScanCode.isNotEmpty) {
        widget.scanCode = inputScanCode;
      }
    }
    if (widget.scanCode != null) {
      _loadOccasionTitle();
    }
  }

  Future<void> _loadOccasionTitle() async {
    if (widget.scanCode == null) return;
    try {
      final occasionData =
          await DbTickets.getOccasionByScanCode(widget.scanCode!);
      if (occasionData != null && mounted) {
        setState(() {
          _occasionTitle = occasionData['title'];
          if (occasionData['features'] != null) {
            _features = (occasionData['features'] as List)
                .map((f) => Feature.fromJson(f))
                .toList();
            final ticketFeature = FeatureService.getFeatureDetails(
                FeatureConstants.ticket,
                features: _features) as TicketFeature?;
            _canScanTicketsManually = ticketFeature?.canScanManually ?? false;
          }
        });
      }
    } catch (e) {
      AppLogger.error("Error loading occasion title: $e");
    }
  }

  Widget buildScannedUserDetails(Color backgroundColor) {
    return ScanResultDisplay(
      scannedObject: _scannedObject,
      scanState: _scanState,
      features: _features,
      fieldMappings: specificFieldMappings,
      showHelpText: _showHelpText,
      backgroundColor: backgroundColor,
      onConfirm: _confirmTicket,
      onResetPassword: _resetPassword,
      onDismissHelp: () {
        setState(() {
          _showHelpText = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool canSearch = AppConfig.isAppSupported || _canScanTicketsManually;

    Color backgroundColor =
        (_scannedObject == null && _scanState == ScanState.nothing)
            ? ThemeConfig.grey200(context)
            : getResultColor(_scanState);

    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: canSearch
          ? FloatingActionButton(
              onPressed: _openSearchDialog,
              tooltip: CommonStrings.search,
              backgroundColor: ThemeConfig.appBarColor(),
              foregroundColor: ThemeConfig.appBarColorNegative(),
              child: const Icon(Icons.search),
            )
          : null,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (_occasionTitle != null)
                  Container(
                    width: double.infinity,
                    color: ThemeConfig.whiteColor(context),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Text(
                      "${OrdersStrings.scanningForOccasion} $_occasionTitle",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: ThemeConfig.blackColor(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Header

                // Display scanned user details
                buildScannedUserDetails(backgroundColor),
                // Scanner view
                Expanded(
                  child: MobileScanner(
                    fit: BoxFit.fitWidth,
                    controller: _mobileScannerController,
                    onDetect: (capture) async {
                      final List<Barcode> barcodes = capture.barcodes;
                      var id = barcodes.firstOrNull;
                      if (id == null) {
                        return;
                      }
                      AppLogger.debug(id.rawValue ?? '');
                      await setupNewId(id.rawValue.toString());
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearchDialog() async {
    // If both are enabled, asking user what to search?
    // Or just search both?
    // For simplicity, if App is Supported, we assume User Search (as per existing behavior).
    // If NOT App Enabled but Ticket Scan Enabled, we use Ticket Search.
    // If BOTH? Maybe a dialog with tabs?
    // Given the prompt "similar to picking users", maybe just one flow.
    // If I search for "John", I might find a User "John" or a Ticket holder "John".
    // I can merge them? Or separate dialogs.

    if (AppConfig.isAppSupported) {
      await _openUserSearchDialog();
    } else if (_canScanTicketsManually) {
      await _openTicketSearchDialog();
    }
  }

  Future<void> _openUserSearchDialog() async {
    List<UserInfoModel> allUsers =
        await DbUsers.getAllUsersBasicsForScan(widget.scanCode!);

    if (!mounted) return;

    final UserInfoModel? selectedUser = await showDialog(
      context: context,
      builder: (ctx) => UserSearchDialog(allUsers: allUsers),
    );

    if (selectedUser != null) {
      await setupNewId(selectedUser.id.toString());
    }
  }

  Future<void> _openTicketSearchDialog() async {
    List<TicketModel> allTickets =
        await DbTickets.getAllTicketsForScan(widget.scanCode!);

    if (!mounted) return;

    final TicketModel? selectedTicket = await showDialog(
      context: context,
      builder: (ctx) => TicketSearchDialog(allTickets: allTickets),
    );

    if (selectedTicket != null) {
      // Use ticket symbol for identification
      if (selectedTicket.ticketSymbol != null) {
        await setupNewId(selectedTicket.ticketSymbol!);
      }
    }
  }

  Future<void> setupNewId(String scannedId) async {
    if (scannedId == rightNowScanned) {
      return;
    }
    rightNowScanned = scannedId;
    _justConfirmed = false;

    _scannedObject = await DbTickets.scanTicket(scannedId, widget.scanCode!);

    if (_scannedObject != null) {
      // 1. Valid (Paid/Sent)
      if (_scannedObject!.state == OrderModel.sentState ||
          _scannedObject!.state == OrderModel.paidState) {
        _scanState = ScanState.valid;
        VibrateService.vibrateOk();
        setState(() {});
        return;
      }
      // 2. Ordered (Valid but Unpaid)
      else if (_scannedObject!.state == OrderModel.orderedState) {
        _scanState = ScanState.ordered;
        VibrateService.vibrateOk();
        setState(() {});
        return;
      }
      // 3. Invalid (Storno)
      else if (_scannedObject!.state == OrderModel.stornoState) {
        _scanState = ScanState.invalid;
        VibrateService.vibrateNotOk();
        setState(() {});
        return;
      }
      // 4. Used
      else if (_scannedObject!.state == OrderModel.usedState) {
        _scanState = ScanState.used;
        VibrateService.vibrateNotOk();
        setState(() {});
        return;
      }
    }

    // Not found in DB or null return
    _scannedObject = null;
    _scanState = ScanState.notFound;
    VibrateService.vibrateNotOk();
    setState(() {});
  }

  Future<void> _confirmTicket() async {
    if (_scannedObject == null) return;

    bool success = await DbTickets.updateTicketToUsed(
        _scannedObject!.id!, widget.scanCode!);

    if (success) {
      setState(() {
        _scannedObject!.state = OrderModel.usedState;
        _scannedObject!.updatedAt = DateTime.now();
        _scanState = ScanState.used;
        _justConfirmed = true;
      });
      VibrateService.vibrateOk();
    } else {
      VibrateService.vibrateNotOk();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OrdersStrings.confirmTicketFailed)),
      );
    }
  }

  Future<void> _resetPassword() async {
    if (_scannedObject == null) return;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(ScanStrings.resetPassword),
          content: Text(OrdersStrings.resetPasswordConfirmationContent(
              _defaultResetPassword)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(CommonStrings.cancel), // Use CommonStrings
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(CommonStrings.reset), // Use CommonStrings
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final result = await DbTickets.resetPassword(
          _scannedObject!.id!, _defaultResetPassword, widget.scanCode!);
      final email = result.email;

      if (!mounted) return;

      if (email != null && email.isNotEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(OrdersStrings.newLoginCredentials),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(OrdersStrings.gridEmail,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(email, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 24),
                Text(CommonStrings.password, // Use CommonStrings
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const SelectableText(_defaultResetPassword,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(CommonStrings.ok), // Use CommonStrings
              ),
            ],
          ),
        );
      } else if (result.failure == PasswordResetFailure.privilegedTarget) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(OrdersStrings.errorResetPasswordPrivilegedUser),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(OrdersStrings.errorEmailNotReturned)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(OrdersStrings.errorResetPassword(e.toString()))),
        );
      }
    }
  }

  Color getResultColor(ScanState scannedState) {
    switch (scannedState) {
      case ScanState.valid:
        return Colors.greenAccent;
      case ScanState.ordered:
        return Colors.orangeAccent;
      case ScanState.used:
        if (_justConfirmed) return Colors.blueAccent;
        return Colors.redAccent;
      case ScanState.invalid:
        return Colors.redAccent;
      case ScanState.notFound:
        return Colors.redAccent;
      case ScanState.nothing:
        return ThemeConfig.backgroundColor(context);
    }
  }
}
