import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/src/layout_editor/layout_localizations.dart';

void main() {
  const cs = VenueLayoutLocalizations(Locale('cs'));
  const en = VenueLayoutLocalizations(Locale('en'));
  test(
    'placement errors are localized and hosts can override their wording',
    () {
      const message = 'Not enough room here. Move the object to a free area.';
      expect(
        cs.text(message),
        'Tady není dost místa. Přesuň objekt na volnou plochu.',
      );
      expect(en.text(message), message);
      expect(cs.text('Locked object: VIP'), 'Zamčený objekt: VIP');
      expect(cs.text('Bad state: Locked object VIP'), 'Zamčený objekt: VIP');
      expect(
        cs.text('Invalid argument(s): Table capacity is 6'),
        'Kapacita stolu je 6 míst.',
      );
      expect(
        cs.text('No collision-free chair position is available'),
        'Pro židli tu není volné místo bez překrývání.',
      );
      expect(cs.text('Table capacity is 6'), 'Kapacita stolu je 6 míst.');
      expect(
        VenueLayoutLocalizations(
          const Locale('cs'),
          overrides: (value) => value == message ? 'Vlastní hláška' : null,
        ).text(message),
        'Vlastní hláška',
      );
    },
  );
  test('assembly and background dialogs use Czech labels and guidance', () {
    const messages = {
      'Preview assembly': 'Náhled sestavy',
      'Rows': 'Řady sedadel',
      'Left seats': 'Sedadel vlevo',
      'Right seats': 'Sedadel vpravo',
      'Rear seats': 'Sedadel vzadu',
      'Seats per compartment': 'Sedadel v kupé',
      'Preview preserves existing seat identities and manual exceptions. Apply commits one change.':
          'Náhled zachová původní sedadla i ruční úpravy. Tlačítko Použít uloží úpravu jako jeden krok.',
      'Text alignment': 'Zarovnání textu',
      'Outline style': 'Styl čáry',
      'Match image aspect ratio': 'Přizpůsobit poměr stran obrázku',
      'Placement alternatives': 'Varianty rozmístění',
    };
    for (final entry in messages.entries) {
      expect(cs.text(entry.key), entry.value);
      expect(en.text(entry.key), entry.key);
    }
  });
  test(
    'dynamic dialog messages preserve counts names and English fallback',
    () {
      expect(
        cs.text('Enter a valid Left seats.'),
        'Zadej platnou hodnotu: Sedadel vlevo.',
      );
      expect(
        cs.text('FormatException: Enter a valid number.'),
        'Zadej platné číslo.',
      );
      expect(
        cs.text('12 editable objects validated'),
        'Zkontrolované upravitelné objekty: 12',
      );
      expect(cs.text('18 placed · 2 unplaced'), 'Umístěno: 18 · Neumístěno: 2');
      expect(
        cs.text('8 seats · spacing 56.0/64.0'),
        '8 sedadel · rozestupy 56.0/64.0',
      );
      expect(cs.text('Export My custom sofa'), 'Exportovat: My custom sofa');
      expect(cs.text('My custom sofa'), 'My custom sofa');
      expect(en.text('18 placed · 2 unplaced'), '18 placed · 2 unplaced');
      expect(
        VenueLayoutLocalizations(
          const Locale('cs'),
          overrides: (text) => text == 'Rows' ? 'Vlastní řady' : null,
        ).text('Rows'),
        'Vlastní řady',
      );
    },
  );
}
