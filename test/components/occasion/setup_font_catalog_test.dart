import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/fonts/ticket_font_catalog.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test('setup catalog retries missing assets and invalid catalog, then matches SQL offline in order', () async {
    const policy = 'automation/tickets/setup-appearance-fonts.json';
    const catalog =
        'supabase/functions/_shared/ticket-assets/font-catalog.json';
    var missingPolicy = true, invalidCatalog = true;
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List());
      if (path == policy && missingPolicy) return null;
      if (path == catalog && invalidCatalog) {
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode('{"version":0}')),
        );
      }
      return ByteData.sublistView(await File(path).readAsBytes());
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    await expectLater(TicketFontCatalog.loadSetupFonts(), throwsA(anything));
    missingPolicy = false;
    await expectLater(
      TicketFontCatalog.loadSetupFonts(),
      throwsFormatException,
    );
    invalidCatalog = false;
    final inFlight = TicketFontCatalog.loadSetupFonts();
    expect(identical(inFlight, TicketFontCatalog.loadSetupFonts()), true);
    final fonts = await inFlight;
    final sql = File('database/functions/occasion_setup/appearance_fonts.sql')
        .readAsStringSync();
    final expected = <String, String>{
      for (final match in RegExp(
        r"WHEN '((?:''|[^'])*)' THEN '([^']*)'",
      ).allMatches(sql))
        match[1]!.replaceAll("''", "'"): match[2]!,
    };
    expect(fonts.length, 1892);
    expect(
      fonts.entries.map((e) => '${e.key}:${e.value}'),
      orderedEquals(expected.entries.map((e) => '${e.key}:${e.value}')),
    );
    expect(() => fonts['new'] = 'invalid', throwsUnsupportedError);
    expect(
      OccasionSetupAppearance.valid({
        'id': 'custom',
        'preserveSource': true,
        'fontFamily': 'Existing custom font',
        'primary': '112233',
        'secondary': '445566',
        'gradient': false,
      }, fonts: null),
      true,
    );
  });
}
