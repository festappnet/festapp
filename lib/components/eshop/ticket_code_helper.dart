import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/scan/scan_page.dart';
import 'package:fstapp/services/dialog_helper.dart';

import 'dart:math';

import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/scan/scan_strings.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/launch_url_service.dart';

class TicketCodeHelper {
  static String generateRandomCode(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  static Future<bool> showScanTicketCode(
    BuildContext context,
    String titleMessage,
    String formLink,
  ) async {
    String? getCode = await DbTickets.getScanCode(formLink);
    if (getCode == null) {
      getCode = generateRandomCode(5);
      await DbTickets.updateScanCode(formLink, getCode);
    }
    String generatedCode = getCode;
    bool result = false;
    String linkBase = "${AppConfig.webLink}/${ScanPage.ROUTE}/";
    String fullLink = linkBase + generatedCode;

    final occasionId = RightsService.currentOccasionId();
    final source = RouterService.getCurrentBrowserUri();
    final returnPath =
        '${source.path}${source.hasQuery ? '?${source.query}' : ''}${source.hasFragment ? '#${source.fragment}' : ''}';
    Future<bool> openScanner(String path, {bool settings = false}) {
      final target = Uri.parse('${AppConfig.webLink}$path').replace(
        queryParameters: {
          'returnTo': returnPath,
          if (settings && occasionId != null) 'occasion': '$occasionId',
        },
      );
      return LaunchUrlService.openExternalUrl(
        target.toString(),
        inCurrentWindow: true,
      );
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            Future<void> handleGenerateCode() async {
              bool confirm = await DialogHelper.showConfirmationDialog(
                context,
                titleMessage,
                OrdersStrings.generateNewCodeWarning,
              );
              if (confirm) {
                String newCode = generateRandomCode(5);
                await DbTickets.updateScanCode(formLink, newCode);
                setState(() {
                  generatedCode = newCode;
                  fullLink = "$linkBase$newCode";
                });
              }
            }

            return AppAlertDialog(
              onClose: () {
                Navigator.of(context).pop();
              },
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Expanded(child: Text(titleMessage))],
              ),
              content: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        OrdersStrings.provideScanLinkInstruction,
                        style: TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  openScanner('/scan/$generatedCode'),
                              child: Text(fullLink),
                            ),
                          ),
                          CopyButton(value: fullLink),
                        ],
                      ),
                      if (occasionId != null &&
                          (RightsService.isEditorOrder() ||
                              RightsService.isEditor())) ...[
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.tune),
                          label: Text(ScanStrings.displaySettings),
                          onPressed: () =>
                              openScanner('/scan/settings', settings: true),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Center(
                        child: ElevatedButton(
                          onPressed: handleGenerateCode,
                          child: Text(OrdersStrings.generateNewCode),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }
}
