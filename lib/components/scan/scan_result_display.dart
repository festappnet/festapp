import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/components/scan/scan_field_mappings.dart';
import 'package:fstapp/components/scan/scan_page.dart';
import 'package:fstapp/components/scan/scan_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';

class ScanResultDisplay extends StatelessWidget {
  final TicketModel? scannedObject;
  final ScanState scanState;
  final List<Feature> features;
  final Map<String, String> fieldMappings;
  final bool showHelpText;
  final Color backgroundColor;
  final VoidCallback onConfirm;
  final VoidCallback onResetPassword;
  final VoidCallback onDismissHelp;

  static const String _defaultResetPassword = "1";
  static const bool _showResetPasswordButton = AppConfig.isAppSupported;

  const ScanResultDisplay({
    super.key,
    required this.scannedObject,
    required this.scanState,
    required this.features,
    required this.fieldMappings,
    required this.showHelpText,
    required this.backgroundColor,
    required this.onConfirm,
    required this.onResetPassword,
    required this.onDismissHelp,
  });

  @override
  Widget build(BuildContext context) {
    Color foregroundColor = ThemeConfig.textColorForBackground(backgroundColor);

    if (scannedObject == null) {
      if (scanState == ScanState.notFound) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child:
                    Icon(Icons.error_outline, size: 60, color: foregroundColor),
              ),
              Text(
                OrdersStrings.scanNotFound,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: foregroundColor,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
              child: Text(ScanStrings.scanCameraInstruction),
            ),
            if (AppConfig.isAppSupported)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: showHelpText ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: InkWell(
                    onTap: onDismissHelp,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        OrdersStrings.scanInstructionsAppUser,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              ThemeConfig.blackColor(context).withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // --- ICONS ---
    IconData icon;
    if (scanState == ScanState.valid) {
      icon = Icons.verified;
    } else if (scanState == ScanState.ordered) {
      icon = Icons.pending_actions;
    } else if (scanState == ScanState.invalid) {
      icon = Icons.block;
    } else if (scanState == ScanState.used) {
      icon = Icons.beenhere;
    } else if (scanState == ScanState.notFound) {
      icon = Icons.error_outline;
    } else {
      return const SizedBox.shrink();
    }

    // Prepare Price and Status Text
    Widget priceWidget = const SizedBox.shrink();
    double? price = getTicketPrice(scannedObject);

    if (price != null) {
      String formattedPrice = Utilities.formatPrice(
        context,
        price,
        currencyCode: scannedObject!.relatedOrder!.currencyCode,
      );

      String statusText = "";
      Color statusColor = foregroundColor;

      if (scanState == ScanState.valid) {
        statusText = OrderModel.stateToLocale(OrderModel.paidState);
      } else if (scanState == ScanState.used) {
        statusText = OrderModel.stateToLocale(OrderModel.usedState);
      } else if (scanState == ScanState.ordered) {
        statusText = OrderModel.stateToLocale(OrderModel.orderedState);
      } else if (scanState == ScanState.invalid) {
        statusText = OrderModel.stateToLocale(OrderModel.stornoState);
      }

      if (statusText.isNotEmpty) {
        priceWidget = Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(fontSize: 20, color: foregroundColor),
              children: [
                TextSpan(
                  text: "$formattedPrice  ",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Prepare State String with Date if Used
    String stateString = OrderModel.stateToLocale(scannedObject!.state);
    if (scannedObject!.state == OrderModel.usedState &&
        scannedObject!.updatedAt != null) {
      String formattedDate =
          DateFormat.yMd().add_jm().format(scannedObject!.updatedAt!);
      stateString += " ($formattedDate)";
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // --- USER DETAILS SECTION ---
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Display related products
                if (scannedObject!.relatedProducts != null &&
                    scannedObject!.relatedProducts!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: scannedObject!.relatedProducts!.map((product) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Column(
                          children: [
                            Text(
                              product.title ?? "",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: foregroundColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (product.description != null &&
                                product.description!.trim().isNotEmpty)
                              HtmlView(
                                html: product.description!,
                                fontSize: 14,
                                color: foregroundColor.withOpacity(0.9),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 8),

                // 2. Customer data, symbol, state
                Text(
                  "${scannedObject!.relatedOrder!.toCustomerData()}   ${scannedObject!.ticketSymbol}   $stateString",
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                // 2b. Display User Groups if available
                if (scannedObject!.relatedGroups != null &&
                    scannedObject!.relatedGroups!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(color: foregroundColor, fontSize: 16),
                        children: [
                          TextSpan(
                            text: OrdersStrings.bigGameLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: scannedObject!.relatedGroups!
                                .map((g) => g.title)
                                .join(", "),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 3. Display Related Spot
                if (scannedObject!.relatedSpot != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      scannedObject!.relatedSpot!.toSpotString(),
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // 4. Price and Payment Status
                priceWidget,

                // 4b. Deposit Info
                if (scannedObject!.depositInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _buildDepositInfoWidget(
                        context, scannedObject!, foregroundColor),
                  ),

                // DISPLAY NOTES
                if (scannedObject!.note != null &&
                    scannedObject!.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      scannedObject!.note!,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (features.isNotEmpty) ...[
                  Builder(builder: (context) {
                    final ticketFeature = FeatureService.getFeatureDetails(
                        FeatureConstants.ticket,
                        features: features) as TicketFeature?;
                    if (ticketFeature?.showHiddenNote == true &&
                        scannedObject!.noteHidden != null &&
                        scannedObject!.noteHidden!.isNotEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          children: [
                            Text(
                              FeaturesStrings.labelShowHiddenNote,
                              style: TextStyle(
                                color: foregroundColor.withOpacity(0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              scannedObject!.noteHidden!,
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                ],

                // 5. Extra fields
                if (scannedObject!.relatedOrder != null)
                  ...fieldMappings.entries.map((entry) {
                    String fieldId = entry.key;
                    String label = entry.value;
                    String? value =
                        getFieldValue(scannedObject!.relatedOrder!, fieldId);

                    if (value == null) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style:
                              TextStyle(color: foregroundColor, fontSize: 15),
                          children: [
                            TextSpan(
                              text: "$label: ",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(text: value),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // --- ICON SECTION ---
          Icon(icon, color: foregroundColor, size: 40),
          const SizedBox(height: 16),

          // --- ACTION BUTTONS SECTION ---

          if (scanState == ScanState.valid || scanState == ScanState.ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ElevatedButton(
                onPressed: onConfirm,
                child: Text(ScanStrings.confirmTicket),
              ),
            ),

          if (_showResetPasswordButton)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              onPressed: onResetPassword,
              child: Text(OrdersStrings.resetPasswordTo(_defaultResetPassword)),
            ),
        ],
      ),
    );
  }

  static Widget _buildDepositInfoWidget(
      BuildContext context, TicketModel ticket, Color foregroundColor) {
    final info = ticket.depositInfo!;
    final isFullyPaid = info['is_fully_paid'] == true;
    final remainingAmount = (info['remaining_amount'] as num?)?.toDouble() ?? 0;
    final deadlineType = info['deadline_type'] as String?;
    final deadlineDate = info['deadline_date'] as String?;
    final currencyCode = ticket.relatedOrder?.currencyCode;

    if (isFullyPaid) {
      return Text(
        OrdersStrings.scanDepositFullyPaid,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: foregroundColor,
        ),
        textAlign: TextAlign.center,
      );
    }

    String formattedRemaining = Utilities.formatPrice(
      context,
      remainingAmount,
      currencyCode: currencyCode,
    );

    String deadlineText = '';
    if (deadlineType == 'on_site') {
      deadlineText = OrdersStrings.scanDepositOnSite;
    } else if (deadlineType == 'date' && deadlineDate != null) {
      try {
        final dt = DateTime.parse(deadlineDate);
        deadlineText = DateFormat.yMd().format(dt);
      } catch (_) {
        deadlineText = deadlineDate;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: foregroundColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: foregroundColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${OrdersStrings.scanDepositCollect}: $formattedRemaining',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: foregroundColor,
            ),
            textAlign: TextAlign.center,
          ),
          if (deadlineText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${OrdersStrings.scanDepositDeadline}: $deadlineText',
              style: TextStyle(
                fontSize: 14,
                color: foregroundColor.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
