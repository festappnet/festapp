import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
// For DateFormat

abstract class IPreviewable {
  String toPreviewString({BuildContext? context});
}

class IdDocumentData implements IPreviewable {
  final String idNumber;
  final DateTime? expiryDate;

  IdDocumentData({
    required this.idNumber,
    this.expiryDate,
  });

  // Factory constructor to create an IdDocumentData instance from a JSON map
  factory IdDocumentData.fromJson(Map<String, dynamic> json) {
    final idNumber = json[IdDocumentFieldHolder.keyIdNumber] as String;

    final expiryDateString =
        json[IdDocumentFieldHolder.keyIdExpiryDate] as String?;
    final DateTime? expiryDate =
        expiryDateString != null ? DateTime.tryParse(expiryDateString) : null;

    return IdDocumentData(
      idNumber: idNumber,
      expiryDate: expiryDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      IdDocumentFieldHolder.keyIdNumber: idNumber,
      IdDocumentFieldHolder.keyIdExpiryDate: expiryDate?.toIso8601String(),
    };
  }

  @override
  String toPreviewString({BuildContext? context}) {
    if (expiryDate != null) {
      String? locale = 'cs_CZ';
      if (context != null) {
        locale = EasyLocalization.of(context)?.locale.toString() ?? 'cs_CZ';
      }
      // Use the locale passed from the context by the caller
      final DateFormat formatter = DateFormat.yMd(locale.toString());
      final String formattedExpiryDate = formatter.format(expiryDate!);
      return "$idNumber ($formattedExpiryDate)";
    } else {
      return idNumber;
    }
  }

  @override
  String toString() {
    return 'IdDocumentData(idNumber: $idNumber, expiryDate: $expiryDate)';
  }
}

class IdDocumentFieldHolder {
  static const String keyIdNumber = "id_document_number";
  static const String keyIdExpiryDate = "id_document_expiry_date";
}
