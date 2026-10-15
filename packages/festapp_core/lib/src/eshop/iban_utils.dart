import 'cz_banks.dart';

class IbanUtils {
  /// Generates a CZ IBAN from parsed components.
  ///
  /// [countryCode] usually "CZ"
  /// [bankCode] 4 digits
  /// [prefix] up to 6 digits (optional, defaults to empty)
  /// [number] up to 10 digits
  ///
  /// Returns validated IBAN or throws exception.
  static String generateCzIban(String bankCode, String prefix, String number) {
    if (bankCode.length != 4 || !RegExp(r'^\d+$').hasMatch(bankCode)) {
      throw FormatException('Invalid bank code length');
    }

    String p = prefix.replaceAll(RegExp(r'\D'), '');
    String n = number.replaceAll(RegExp(r'\D'), '');

    // CZ Account Structure:
    // Prefix: max 6 digits
    // Number: max 10 digits
    // Bank: 4 digits

    if (p.length > 6) throw FormatException('Prefix too long');
    if (n.length > 10) throw FormatException('Account number too long');
    if (n.isEmpty) throw FormatException('Account number empty');

    // Validation of mod 11 for prefix and number separately
    if (p.isNotEmpty && !_checkMod11(p)) {
      throw FormatException('Invalid prefix checksum (Mod 11)');
    }
    if (!_checkMod11(n)) {
      throw FormatException('Invalid account number checksum (Mod 11)');
    }

    // Pad prefix to 6, number to 10
    String paddedPrefix = p.padLeft(6, '0');
    String paddedNumber = n.padLeft(10, '0');

    // Calculate Checksum digits
    // Format for calculation: BankCode + Prefix + Number + CountryCodeNum + "00"
    // CZ = 1235 (C=12, Z=35)

    String countryCodeNum = "1235"; // C=12, Z=35
    String bban = "$bankCode$paddedPrefix$paddedNumber";
    String numericString = "$bban${countryCodeNum}00";

    int mod97 = _calcMod97(numericString);
    int checkDigits = 98 - mod97;
    String checkString = checkDigits.toString().padLeft(2, '0');

    return "CZ$checkString$bankCode$paddedPrefix$paddedNumber";
  }

  static bool _checkMod11(String numberStr) {
    // Weights: ... 8 4 2 1 6 3 7 9 10 5 8 4 2 1
    // But for CZ account numbers (max 10) and prefix (max 6), weights repeat logic.
    // Standard CZ weights from right to left: 1, 2, 4, 8, 5, 10, 9, 7, 3, 6

    // Weights for 10 digits (from left to right matching the position):
    // Pos: 1  2  3  4  5  6  7  8  9  10
    // Wgt: 6  3  7  9 10  5  8  4  2   1

    // Use explicit weights array for max 10 digits.
    List<int> weights = [6, 3, 7, 9, 10, 5, 8, 4, 2, 1];

    // Pad to 10 for easier logic (prefix is handled as separate entity)
    String padded = numberStr.padLeft(10, '0');

    int sum = 0;
    for (int i = 0; i < 10; i++) {
      int digit = int.parse(padded[i]);
      sum += digit * weights[i];
    }

    return sum % 11 == 0;
  }

  static int _calcMod97(String numericString) {
    // Handle large numbers by parsing in chunks
    String remainder = "";
    for (int i = 0; i < numericString.length; i += 7) {
      String chunk =
          remainder +
          numericString.substring(
            i,
            (i + 7 < numericString.length) ? i + 7 : numericString.length,
          );
      int val = int.parse(chunk);
      remainder = (val % 97).toString();
    }
    return int.parse(remainder);
  }

  static bool isValidIban(String iban) {
    // Basic formatting
    String clean = iban.replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{4,30}$').hasMatch(clean)) return false;

    // Country specific Check
    // For now assuming CZ
    if (clean.startsWith('CZ')) {
      if (clean.length != 24) return false;
    }

    // Move first 4 chars to end
    String moved = clean.substring(4) + clean.substring(0, 4);

    // Convert letters to numbers (A=10, Z=35)
    StringBuffer numeric = StringBuffer();
    for (int i = 0; i < moved.length; i++) {
      int code = moved.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        // 0-9
        numeric.write(String.fromCharCode(code));
      } else if (code >= 65 && code <= 90) {
        // A-Z
        numeric.write((code - 55).toString());
      } else {
        return false;
      }
    }

    return _calcMod97(numeric.toString()) == 1;
  }

  static ParsedAccount? parseCzIban(String iban) {
    String clean = iban.replaceAll(' ', '').toUpperCase();
    if (!clean.startsWith('CZ') || clean.length != 24) return null;
    if (!isValidIban(clean)) return null;

    // CZkk bbbb pppp ppaa aaaa aaaa
    String bankCode = clean.substring(4, 8);
    String prefixStr = clean.substring(8, 14);
    String numberStr = clean.substring(14, 24);

    int prefix = int.parse(prefixStr);
    int number = int.parse(numberStr);

    return ParsedAccount(
      bankCode: bankCode,
      bankName: czBanks[bankCode] ?? '',
      prefix: prefix.toString(),
      number: number.toString(),
    );
  }
}

class ParsedAccount {
  final String bankCode;
  final String bankName;
  final String prefix;
  final String number;

  ParsedAccount({
    required this.bankCode,
    required this.bankName,
    required this.prefix,
    required this.number,
  });
}
