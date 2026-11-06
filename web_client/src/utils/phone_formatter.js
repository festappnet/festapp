
export class PhoneFormatter {
    static kMaxPhoneNumberLength = 12;

    static formatInput(inputElement) {
        const oldValue = inputElement.value;
        const cursorPosition = inputElement.selectionEnd;

        // 1. Clean
        let cleaned = PhoneFormatter.cleanPhoneNumber(oldValue);

        // 2. Format
        let formatted = PhoneFormatter.formatPhoneNumber(cleaned);

        // 3. Handle specific "Smart Space" case from Flutter?
        // Flutter logic: "Smart space handling: if user typed a space at the end and it's a valid separator position, keep it."
        // In JS input event, the space is already in 'oldValue' (which is the current value of the input).
        // But 'cleaned' removes it. 'formatted' puts it back safely IF it belongs there.
        // The one edge case is if the user types a space that IS NOT yet in the formatted string (e.g. they type space early).
        // But Flutter's formater logic forces the format 123 456. User can't type space elsewhere.
        // The Flutter "Smart Space" block:
        // if (newValue.text.endsWith(' ') && (cleaned.length == 4 || cleaned.length == 7 || cleaned.length == 10))
        // This effectively allows the cursor to "rest" after a space if the user typed it at the right spot, 
        // preventing the formatter from stripping it and pulling the cursor back if the next digit hasn't been typed yet?
        // Actually, if 'formatted' doesn't have the space yet (e.g. maybe logic doesn't add trailing space?), we add it.

        /*
           Flutter's formatting logic:
           cleaned: "123"
           formatted: "123"
           User types space -> "123 "
           cleaned: "123"
           formatted: "123"
           Result: "123" (Space removed).
           
           Flutter fix:
           if text ends with space & len is 3 (cleaned len=3), and formatted doesn't have space, add it.
           "123 " -> cleaned "123" (len 3).
           formatted "123".
           formatted += " " -> "123 ".
           
           Note: Flutter's loop `if (i > 0 && i % 3 == 0)` adds space BEFORE the digit.
           So "123" becomes "123".
           "1234" becomes "123 4".
           It does NOT add trailing space automatically.
           So we DO need that "Smart Space" logic to allow the user to see the space they typed.
        */
        
        if (oldValue.endsWith(' ') && (cleaned.length === 3 || cleaned.length === 6 || cleaned.length === 9 || (cleaned.startsWith('+') && cleaned.length === 4))) {
             // Logic adaptation:
             // Flutter checks 4, 7, 10. That's likely for +420 123 456 formatting.
             // If I have "123", len=3. Format is 123 456. space at 3?
             // Without +, groups of 3: 123 456. So after 3, 6, 9.
             // Flutter: `cleaned.length == 4 || cleaned.length == 7 || cleaned.length == 10`
             // Wait, if input is +420 (len 4), format is "+420 ".
             // If input is 1234 (len 4), format is "123 4". space is after 3rd char.
             
             // Let's stick to the visual behavior:
             // If formatting doesn't add a space at the end, but we are at a boundary, add it.
             if (!formatted.endsWith(' ')) {
                 formatted += ' ';
             }
        }
        
        // Update Value
        inputElement.value = formatted;

        // 4. Cursor Position
        // Count non-space chars before old cursor
        let digitsBeforeCursor = 0;
        for (let i = 0; i < cursorPosition && i < oldValue.length; i++) {
             // We count 'digits' (everything that survives cleaning basically? or just not space?)
             // Flutter: `if (text[i] != ' ') digitsBeforeCursor++;`
             if (oldValue[i] !== ' ') digitsBeforeCursor++;
        }

        let newCursorIndex = 0;
        let currentDigits = 0;
        for (let i = 0; i < formatted.length; i++) {
            if (formatted[i] !== ' ') currentDigits++;
            if (currentDigits > digitsBeforeCursor) break;
            // If we match exactly, and the next char is a space, should we jump over it?
            // Usually standard behavior is to sit before the space if we just finished the group,
            // or after if we are typing. 
            // Flutter loop creates `newCursorIndex` which is incremented.
            newCursorIndex++;
        }
        
        inputElement.setSelectionRange(newCursorIndex, newCursorIndex);
    }

    static cleanPhoneNumber(text) {
        // Remove all non-digit characters except leading +
        // JS: Replace everything that is NOT digit and NOT +
        let cleaned = text.replace(/[^\d+]/g, '');
        
        // Handle + only at clear start
        if (cleaned.includes('+')) {
            if (cleaned.startsWith('+')) {
                // Keep first +, remove others
                cleaned = '+' + cleaned.substring(1).replace(/\+/g, '');
            } else {
                // Remove all +
                cleaned = cleaned.replace(/\+/g, '');
            }
        }

        // Enforce max length
        // We count digits only for length check? Flutter: `cleaned.replaceAll('+', '').length`
        let digitCount = cleaned.replace(/\+/g, '').length;
        
        if (digitCount > PhoneFormatter.kMaxPhoneNumberLength) {
             // Truncate
             // Need to find where to cut. 
             // Simplest: just take substring, but be careful of '+'
             // If starts with +, max length is k + 1
             if (cleaned.startsWith('+')) {
                 cleaned = cleaned.substring(0, PhoneFormatter.kMaxPhoneNumberLength + 1);
             } else {
                 cleaned = cleaned.substring(0, PhoneFormatter.kMaxPhoneNumberLength);
             }
        }
        return cleaned;
    }

    static formatPhoneNumber(cleaned) {
        let formatted = '';
        if (cleaned.startsWith('+')) {
            // +420123456
            if (cleaned.length > 4) {
                 // +420 123...
                 formatted = cleaned.substring(0, 4) + ' ' + cleaned.substring(4);
                 
                 // Handle the rest: 123456 -> 123 456
                 // current formatted: "+420 123456"
                 // We need to re-process the part after the space
                 let prefix = formatted.substring(0, 5); // "+420 "
                 let rest = formatted.substring(5);
                 
                 let spacedRest = '';
                 for (let i = 0; i < rest.length; i++) {
                     if (i > 0 && i % 3 === 0) spacedRest += ' ';
                     spacedRest += rest[i];
                 }
                 formatted = prefix + spacedRest;
            } else {
                 formatted = cleaned;
            }
        } else {
            // 123456 -> 123 456
            for (let i = 0; i < cleaned.length; i++) {
                if (i > 0 && i % 3 === 0) formatted += ' ';
                formatted += cleaned[i];
            }
        }
        return formatted;
    }
}
