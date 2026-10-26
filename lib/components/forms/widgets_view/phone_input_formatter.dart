import 'package:flutter/services.dart';

class PhoneInputFormatter extends TextInputFormatter {
  static const int kMaxPhoneNumberLength = 12;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    int cursorIndex = newValue.selection.end;

    // Handle backspace of space: delete the digit before it
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldValue.text.length == newValue.text.length + 1) {
      final deletedCharIndex = newValue.selection.end;
      if (deletedCharIndex < oldValue.text.length &&
          oldValue.text[deletedCharIndex] == ' ') {
        // Space was deleted. Remove the character before it (the digit)
        if (newValue.selection.end > 0) {
          text = text.substring(0, newValue.selection.end - 1) +
              text.substring(newValue.selection.end);
          cursorIndex--;
        }
      }
    }

    if (text.isEmpty) return newValue.copyWith(text: '');

    // Clean and enforce max length
    String cleaned = cleanPhoneNumber(text);

    // Format
    String formatted = formatPhoneNumber(cleaned);

    // Smart space handling: if user typed a space at the end and it's a valid separator position, keep it.
    if (newValue.text.endsWith(' ') &&
        (cleaned.length == 4 || cleaned.length == 7 || cleaned.length == 10)) {
      if (!formatted.endsWith(' ')) {
        formatted += ' ';
      }
    }

    // Recalculate cursor position
    int digitsBeforeCursor = 0;
    for (int i = 0; i < cursorIndex && i < text.length; i++) {
      if (text[i] != ' ') digitsBeforeCursor++;
    }

    int newCursorIndex = 0;
    int currentDigits = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (formatted[i] != ' ') currentDigits++;
      if (currentDigits > digitsBeforeCursor) break;
      newCursorIndex++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
          offset: newCursorIndex.clamp(0, formatted.length)),
    );
  }

  static String cleanPhoneNumber(String text) {
    // Remove all non-digit characters except leading +
    String cleaned = text.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) {
      cleaned = '+${cleaned.substring(1).replaceAll('+', '')}';
    } else {
      cleaned = cleaned.replaceAll('+', '');
    }

    // Enforce max length
    int currentDigits = cleaned.replaceAll('+', '').length;
    if (currentDigits > kMaxPhoneNumberLength) {
      if (cleaned.startsWith('+')) {
        cleaned = cleaned.substring(0, kMaxPhoneNumberLength + 1);
      } else {
        cleaned = cleaned.substring(0, kMaxPhoneNumberLength);
      }
    }
    return cleaned;
  }

  static String formatPhoneNumber(String cleaned) {
    String formatted = '';
    if (cleaned.startsWith('+')) {
      // +420123456
      if (cleaned.length > 4) {
        formatted = '${cleaned.substring(0, 4)} ${cleaned.substring(4)}';
        // Now handle the rest: 123456 -> 123 456
        String rest = formatted.substring(5);
        String spacedRest = '';
        for (int i = 0; i < rest.length; i++) {
          if (i > 0 && i % 3 == 0) spacedRest += ' ';
          spacedRest += rest[i];
        }
        formatted = formatted.substring(0, 5) + spacedRest;
      } else {
        formatted = cleaned;
      }
    } else {
      // 123456 -> 123 456
      for (int i = 0; i < cleaned.length; i++) {
        if (i > 0 && i % 3 == 0) formatted += ' ';
        formatted += cleaned[i];
      }
    }
    return formatted;
  }
}
