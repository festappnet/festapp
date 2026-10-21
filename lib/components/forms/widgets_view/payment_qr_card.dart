import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// "Scan to pay" card shown on the public order confirmation when the form has
/// `show_payment_qr` enabled. The currency-aware payload is produced
/// server-side and delivered with the order data; this widget renders it plus
/// the human-readable payment details. Layout mirrors the deployed build:
/// title, subtitle, QR, then bankAccount / IBAN(if different) / variableSymbol
/// / amountToPay / paymentNote(if any) — every row copyable — then a
/// "Download QR" button.
class PaymentQrCard extends StatelessWidget {
  final String payload;
  final String format;
  final String? occasionTitle;
  final String? orderSymbol;

  /// Human-readable account number (shown as "Bank account").
  final String? bankAccount;

  /// Machine account number / IBAN (shown only when different from [bankAccount]).
  final String? iban;
  final String? paymentReference;
  final String? referenceKind;
  final String? amountFormatted;
  final String? note;

  const PaymentQrCard({
    super.key,
    required this.payload,
    required this.format,
    this.occasionTitle,
    this.orderSymbol,
    this.bankAccount,
    this.iban,
    this.paymentReference,
    this.referenceKind,
    this.amountFormatted,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    void addRow(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(_CopyRow(label: label, value: value));
    }

    addRow(PublicOrderStrings.bankAccount, bankAccount);
    // IBAN only when it differs from the human-readable account.
    if ((iban?.isNotEmpty ?? false) && iban != bankAccount) {
      rows.add(_CopyRow(label: PublicOrderStrings.iban, value: iban!));
    }
    addRow(
      referenceKind == 'RF'
          ? PublicOrderStrings.paymentReference
          : PublicOrderStrings.variableSymbol,
      paymentReference,
    );
    addRow(PublicOrderStrings.amountToPay, amountFormatted);
    addRow(PublicOrderStrings.paymentNote, note);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              PublicOrderStrings.paymentQrTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              PublicOrderStrings.paymentQrSubtitle,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...rows,
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: Text(PublicOrderStrings.downloadQr),
              onPressed: () => _downloadQr(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadQr(BuildContext context) async {
    try {
      final painter = QrPainter(
        data: payload,
        version: QrVersions.auto,
        gapless: true,
      );
      final picData = await painter.toImageData(512);
      if (picData == null) return;
      String filenamePart(String? value) => Utilities.removeDiacritics(value ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final filename = [
        filenamePart(occasionTitle),
        'objednavka',
        filenamePart(orderSymbol ?? paymentReference),
        'qr',
      ].where((part) => part.isNotEmpty).join('-');
      await FileSaver.instance.saveFile(
        name: filename,
        bytes: picData.buffer.asUint8List(),
        fileExtension: 'png',
        mimeType: MimeType.png,
      );
    } catch (_) {
      // ignore — download is best-effort
    }
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  const _CopyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(text: '$label: ', style: theme.textTheme.bodyMedium),
                  TextSpan(
                    text: value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ToastHelper.Show(context, PublicOrderStrings.copied);
              }
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.copy, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
