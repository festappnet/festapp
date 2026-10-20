import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Package-owned English/Czech messages using Flutter's locale resolution.
/// English source messages are the fallback for untranslated or custom content.
class VenueLayoutLocalizations {
  const VenueLayoutLocalizations(this.locale, {this.overrides});
  final Locale locale;
  final String? Function(String message)? overrides;
  static const supportedLocales = [Locale('en'), Locale('cs')];
  static const LocalizationsDelegate<VenueLayoutLocalizations> delegate =
      _VenueLayoutLocalizationsDelegate();
  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static VenueLayoutLocalizations of(BuildContext context) =>
      Localizations.of<VenueLayoutLocalizations>(
        context,
        VenueLayoutLocalizations,
      ) ??
      const VenueLayoutLocalizations(Locale('en'));

  String text(String message) =>
      overrides?.call(message) ??
      (locale.languageCode == 'cs' ? _czechLayoutText(message) : message);
  String get table => text('Table');
  String get couch => text('Couch');
  String tableName(int number) => '$table $number';
}

class _VenueLayoutLocalizationsDelegate
    extends LocalizationsDelegate<VenueLayoutLocalizations> {
  const _VenueLayoutLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => VenueLayoutLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);
  @override
  Future<VenueLayoutLocalizations> load(Locale locale) =>
      SynchronousFuture(VenueLayoutLocalizations(locale));
  @override
  bool shouldReload(_VenueLayoutLocalizationsDelegate old) => false;
}

String _czechLayoutText(String text) {
  final direct = _cs[text];
  if (direct != null) return direct;
  final available = RegExp(r'^(\d+) available$').firstMatch(text);
  if (available != null) return 'Volných: ${available[1]}';
  final selectedSeats = RegExp(r'^(\d+) seats selected$').firstMatch(text);
  if (selectedSeats != null) return 'Vybraná místa: ${selectedSeats[1]}';
  final selectionResult = RegExp(
    r'^(\d+) seats? (selected|released)\.$',
  ).firstMatch(text);
  if (selectionResult != null) {
    return '${selectionResult[2] == 'selected' ? 'Vybraná' : 'Uvolněná'} místa: ${selectionResult[1]}';
  }
  final validValue = RegExp(r'^Enter a valid (.+)\.$').firstMatch(text);
  if (validValue != null) {
    return 'Zadej platnou hodnotu: ${_czechLayoutText(validValue[1]!)}.';
  }
  final validated = RegExp(
    r'^(\d+) editable objects validated$',
  ).firstMatch(text);
  if (validated != null) {
    return 'Zkontrolované upravitelné objekty: ${validated[1]}';
  }
  final placed = RegExp(r'^(\d+) placed · (\d+) unplaced$').firstMatch(text);
  if (placed != null) {
    return 'Umístěno: ${placed[1]} · Neumístěno: ${placed[2]}';
  }
  final spacing = RegExp(
    r'^(\d+) seats · spacing ([\d.]+)/([\d.]+)$',
  ).firstMatch(text);
  if (spacing != null) {
    return '${spacing[1]} sedadel · rozestupy ${spacing[2]}/${spacing[3]}';
  }
  final remaining = RegExp(
    r'^(\d+) more objects\. Refine search to find them\.$',
  ).firstMatch(text);
  if (remaining != null) {
    return 'Další objekty: ${remaining[1]}. Upřesni hledání.';
  }
  final sourcePoint = RegExp(
    r'^1\. Tap two recognizable points on the source image \((\d+)/2\)\.$',
  ).firstMatch(text);
  if (sourcePoint != null) {
    return '1. Vyber dva rozpoznatelné body v podkladovém obrázku (${sourcePoint[1]}/2).';
  }
  final targetPoint = RegExp(
    r'^2\. Tap the matching plan positions in the same order \((\d+)/2\)\.$',
  ).firstMatch(text);
  if (targetPoint != null) {
    return '2. Ve stejném pořadí vyber odpovídající body v plánku (${targetPoint[1]}/2).';
  }
  final template = RegExp(
    r'^Use (.+)\. Your current plan can be restored with Undo\.$',
  ).firstMatch(text);
  if (template != null) {
    return 'Použít: ${_czechLayoutText(template[1]!)}. Současný plánek obnovíš akcí Zpět.';
  }
  final locked = RegExp(r'^Locked (?:couch )?object:? (.+)$').firstMatch(text);
  if (locked != null) return 'Zamčený objekt: ${locked[1]}';
  final tableCapacity = RegExp(r'^Table capacity is (\d+)$').firstMatch(text);
  if (tableCapacity != null) {
    return 'Kapacita stolu je ${tableCapacity[1]} míst.';
  }
  for (final prefix in [
    'FormatException: ',
    'Bad state: ',
    'Invalid argument(s): ',
  ]) {
    if (text.startsWith(prefix)) {
      final message = text.substring(prefix.length);
      final translated = _czechLayoutText(message);
      if (translated != message) return translated;
    }
  }
  if (text.startsWith('Export ')) return 'Exportovat: ${text.substring(7)}';
  if (text.startsWith('Rendering issue: ')) {
    return 'Chyba zobrazení: ${text.substring(17)}';
  }
  final resize = RegExp(
    r'^Resize (n|e|s|w|nw|ne|sw|se) handle$',
  ).firstMatch(text);
  if (resize != null) {
    const directions = {
      'n': 'horní hrana',
      'e': 'pravá hrana',
      's': 'dolní hrana',
      'w': 'levá hrana',
      'nw': 'levý horní roh',
      'ne': 'pravý horní roh',
      'sw': 'levý dolní roh',
      'se': 'pravý dolní roh',
    };
    return 'Změnit velikost - ${directions[resize[1]]}';
  }
  final removed = RegExp(
    r'^Seats removed: (\d+)\. Undo restores them\.$',
  ).firstMatch(text);
  if (removed != null) {
    return 'Odebraná sedadla: ${removed[1]}. Akce Zpět je obnoví.';
  }
  final points = RegExp(
    r'^(\d+) vertices\. Tap to add; Enter to finish\.$',
  ).firstMatch(text);
  if (points != null) return 'Počet bodů: ${points[1]}';
  final vertex = RegExp(r'^Vertex (\d+) handle$').firstMatch(text);
  if (vertex != null) return 'Bod čáry ${int.parse(vertex[1]!) + 1}';
  if (text.startsWith('Canvas resize ') && text.endsWith(' handle')) {
    final direction = text
        .substring('Canvas resize '.length)
        .replaceFirst(' handle', '');
    const edges = {
      'n': 'horní hrana',
      'e': 'pravá hrana',
      's': 'dolní hrana',
      'w': 'levá hrana',
      'nw': 'levý horní roh',
      'ne': 'pravý horní roh',
      'sw': 'levý dolní roh',
      'se': 'pravý dolní roh',
    };
    return 'Změnit velikost plátna - ${edges[direction] ?? direction}';
  }
  if (text.startsWith('Place ')) {
    return 'Vložit: ${_czechLayoutText(text.substring(6))}';
  }
  if (text.startsWith('Apply ')) {
    return 'Použít: ${_czechLayoutText(text.substring(6))}';
  }
  if (text.startsWith('Tap the plan to place ')) {
    return 'Kliknutím do plánku vložíš: ${_czechLayoutText(text.substring('Tap the plan to place '.length).replaceFirst(RegExp(r'\.$'), ''))}';
  }
  final capacity = RegExp(r'^(\d+) seats · maximum (\d+)$').firstMatch(text);
  if (capacity != null) return '${capacity[1]} míst · maximum ${capacity[2]}';
  final count = RegExp(r'^(\d+) seats · (\d+) standing$').firstMatch(text);
  if (count != null) return '${count[1]} míst k sezení · ${count[2]} ke stání';
  final multiple = RegExp(
    r'^(\d+) objects selected\. Individual values vary\.$',
  ).firstMatch(text);
  if (multiple != null) return 'Vybrané objekty: ${multiple[1]}';
  final selected = RegExp(r'^(\d+) selected ·').firstMatch(text);
  if (selected != null) {
    return 'Vybráno: ${selected[1]} · Shift + klik přidá do výběru · Alt vybere jednotlivý prvek';
  }
  if (text.startsWith('Saved local baseline, revision ')) {
    return 'Plánek uložený v tomto prohlížeči';
  }
  return text;
}

const _cs = <String, String>{
  'Center': 'Na střed',
  'Right': 'Vpravo',
  'Chair gap': 'Mezera u židle',
  'Chair height': 'Výška židle',
  'Chair spacing': 'Rozestup židlí',
  'Change bar side': 'Změnit stranu baru',
  'Change selected colors': 'Změnit vybrané barvy',
  'Edge padding': 'Odsazení od hrany',
  'Enter a valid whole seat count.': 'Zadej platný počet míst jako celé číslo.',
  'Resize grid surface': 'Změnit rozměry vlastní plochy',
  'Seats': 'Počet míst',
  'Text style': 'Řez písma',

  'Underline': 'Podtržení',
  'Contain': 'Zachovat poměr stran',
  'contain': 'Zachovat poměr stran',
  'fill': 'Vyplnit',
  'crop': 'Oříznout',
  'none': 'Žádný',
  'override': 'Vlastní',
  'inherit': 'Zdědit',
  'top': 'Nahoře',
  'bottom': 'Dole',
  'edgePadding': 'Odsazení od hrany',
  'seatsPerRow': 'Míst v řadě',
  'rowSpacing': 'Rozestup řad',
  'minSeatWidth': 'Minimální šířka sedadla',
  'minSeatHeight': 'Minimální výška sedadla',
  'upperRows': 'Řady v patře',
  'upperRear': 'Zadní sedadla v patře',
  'rear': 'Zadní sedadla',
  'decks': 'Počet pater',
  'compartments': 'Kupé',
  'bus': 'Autobus',
  'rows': 'Řady',
  'blocks': 'Bloky',
  'aisle': 'Ulička',
  'arc': 'Zakřivení',
  'spacing': 'Rozestup',
  'Language': 'Jazyk',

  'This font does not provide all bold and italic faces. Choose another font to use them.':
      'Toto písmo nemá všechny tučné a kurzívní řezy. Pro jejich použití vyberte jiné písmo.',
  'Save as style': 'Uložit jako styl…',
  'Save style': 'Uložit styl',
  'Style name': 'Název stylu',
  'Style actions': 'Další akce se stylem',
  'My styles': 'Moje styly',
  'Rename style': 'Přejmenovat styl',
  'Delete style': 'Odstranit styl',
  'No saved styles yet.': 'Zatím nemáte uložené styly.',
  'Enter a style name.': 'Zadejte název stylu.',
  'A style with this name already exists.': 'Styl s tímto názvem už existuje.',
  'Insert image': 'Vložit obrázek',
  'Insert SVG': 'Vložit SVG',
  'Galaxy cinema': 'Galaktické kino',
  'Dark cinema with seven rows, 84 seats and four two-seat sofas':
      'Tmavé kino se sedmi řadami, 84 místy a čtyřmi dvojmístnými gauči',
  'Restore automatic position': 'Vrátit k automatickému rozmístění',
  'Insert image / SVG': 'Vložit obrázek / SVG',
  'Set as default font for the plan': 'Použít písmo v celém plánku',
  'Apply to': 'Upravuji vzhled pro',
  'Advanced appearance': 'Podrobnosti vzhledu',
  'Position and size': 'Poloha a velikost',

  'Regular': 'Normální',

  'Material': 'Styl konstrukce',
  'Chair style': 'Styl sedadla',
  'Dash lengths': 'Délky čárek',
  'Label orientation': 'Orientace popisku',
  'round': 'Kulatý',
  'simple': 'Jednoduchý',
  'minimal': 'Minimalistický',
  'wood': 'Dřevěný',
  'lounge': 'Čalouněný',
  'transit': 'Dopravní',
  'hall': 'Sálový',
  'banquet': 'Slavnostní',
  'plain': 'Jednoduchý',
  'upholstered': 'Čalouněný',
  'roundUpholstered': 'Kulatý čalouněný',
  'solid': 'Plná',
  'dashed': 'Čárkovaná',
  'dotted': 'Tečkovaná',
  'custom': 'Vlastní',

  'Style family': 'Stylová rodina',
  'Detailed settings': 'Podrobné nastavení',
  'Default': 'Výchozí',
  'Alignment': 'Zarovnání',
  'Direction': 'Směr textu',
  'auto': 'Automaticky',
  'ltr': 'Zleva doprava',
  'rtl': 'Zprava doleva',
  'object': 'S objektem',
  'screen': 'Podle obrazovky',
  'image': 'Obrázky',
  'vector': 'Vektorová grafika',

  'Own value': 'Vlastní hodnota',
  'Inherited value': 'Zděděná hodnota',
  'Reset to inherited value': 'Obnovit zděděnou hodnotu',
  'All labels': 'Všechny popisky',
  'Object': 'Objekt',
  'Table chair style': 'Styl židlí stolu',
  'Kind style': 'Styl typu objektu',
  'Font does not include this face': 'Písmo neobsahuje tento řez',
  'Font family': 'Rodina písma',
  'Object style': 'Styl objektu',

  'available': 'Volné',
  'Available': 'Volné',
  'occupied': 'Obsazené',
  'reserved': 'Rezervované',
  'blocked': 'Blokované',
  'pending': 'Zpracovává se',
  'unavailable': 'Nedostupné',
  'disabled': 'Zakázané',
  'sold': 'Prodané',
  'Bar': 'Bar',
  'Bar stools must stay on the guest side.':
      'Barová místa musí zůstat na straně pro hosty.',
  'This bar side is too short for its stools.':
      'Tato strana baru je pro stávající místa příliš krátká.',
  'Bar guest side must be top, right, bottom or left.':
      'Vyber platnou stranu baru pro hosty.',
  'Bar stool': 'Barová stolička',
  'Bar and stools': 'Bar a barová místa',
  'Guest side': 'Strana pro hosty',
  'Table side': 'Strana stolu',
  'Change chair side': 'Změnit stranu židle',
  'Not enough room on the selected table side':
      'Na vybrané straně stolu není dost místa.',
  'Top side': 'Horní',
  'Right side': 'Pravá',
  'Bottom side': 'Dolní',
  'Left side': 'Levá',
  'Stools occupy one side; the opposite side stays clear for staff.':
      'Místa jsou na jedné straně. Protilehlá strana zůstává volná pro obsluhu.',
  'Change bar guest side': 'Změnit stranu hostů u baru',
  'Cannot place stools on this side. Enlarge or move the bar, or reduce the seat count.':
      'Na tuto stranu nelze místa umístit. Zvětši nebo přesuň bar, případně sniž počet míst.',

  'Round': 'Kulatý',
  'Soft corners': 'Oblé',
  'Round seating': 'Kulatá sedadla',
  'Circular seat markers and simple table outlines.':
      'Kulaté značky míst a jednoduché obrysy stolů.',
  'Modern': 'Moderní',
  'Banquet hall': 'Slavnostní sál',
  'Tapered banquet chairs, bowed backs and timber tables.':
      'Tvarované společenské židle, prohnutá opěradla a dřevěné stoly.',
  'Chair layout': 'Rozmístění židlí',
  'Chair size': 'Velikost židle',
  'Advanced chair settings': 'Pokročilé nastavení židlí',
  'Chairs in preview': 'Židle v náhledu',
  'Fewer chairs': 'Méně židlí',
  'More chairs': 'Více židlí',
  'Only changes the preview. The table stays the same size.':
      'Mění pouze náhled. Stůl zůstává stejně velký.',
  'Double-click to reset': 'Dvojklikem obnovíš výchozí hodnotu',
  'The table is full. Reduce the chair size or spacing.':
      'Stůl je plný. Zmenši židle nebo mezery mezi nimi.',
  'Distance from table corners': 'Odstup od rohů stolu',
  'Unable to change chair layout. Reduce the values or free up space around the tables.':
      'Rozmístění židlí nelze změnit. Sniž hodnoty nebo uvolni místo kolem stolů.',
  'Chair width': 'Šířka židle',
  'Chair depth': 'Hloubka židle',
  'Distance from table': 'Odstup od stolu',
  'Applies to existing and new tables. Manual chair positions and locked assemblies stay unchanged.':
      'Platí pro stávající i nové stoly. Ruční rozmístění židlí a zamčené sestavy zůstanou zachované.',
  'Unable to change chair distance. Reduce the distance or free up space around the tables.':
      'Odstup židlí nelze změnit. Zmenši odstup nebo uvolni místo kolem stolů.',
  'Space between chairs': 'Mezera mezi židlemi',
  'Adjust chair layout': 'Upravit rozmístění židlí',
  'Minimal': 'Minimalistický',
  'Original': 'Původní',
  'Original seat markers and simple table outlines.':
      'Původní značky míst a jednoduché obrysy stolů.',
  'Banquet': 'Společenské',
  'Chairs move with the table. Resize handles change the tabletop.':
      'Židle se přesouvají se stolem. Úchyty mění velikost desky.',
  'Scout ball - hall with balcony': 'Skautský ples - sál s balkónem',
  'Original 249 seats, side tables, balcony, stage and stairs':
      'Původních 249 míst, boční stoly, balkón, pódium a schodiště',
  'Traditional hall': 'Tradiční sál',
  'Rounded banquet tables and timber hall chairs.':
      'Zaoblené banketové stoly a dřevěné sálové židle.',
  'Scout ball - original hall': 'Skautský ples - původní sál',
  'Original 182 seats, 31 tables, stage, dance floor and columns':
      'Původních 182 míst, 31 stolů, pódium, parket a sloupy',
  'Timber': 'Dřevěný',
  'Clean silhouettes and light construction.':
      'Čisté siluety a lehká konstrukce.',
  'Wooden frames, shaped seats and crafted tables.':
      'Dřevěné rámy, tvarované sedáky a propracované stoly.',
  'Soft armchairs, padded seating and rounded furniture.':
      'Měkká křesla, čalouněné sezení a oblé vybavení.',
  'Fine-tune appearance': 'Doladit vzhled',

  'Color palette': 'Barevná paleta',
  'Colors': 'Barvy',
  'Clear selection': 'Zrušit výběr',
  'Live preview': 'Živý náhled',
  'Standing places are unavailable.': 'Místa k stání nejsou dostupná.',
  'Chair appearance': 'Vzhled židlí',
  'Simple': 'Jednoduché',
  'Wooden': 'Dřevěné',
  'Upholstered': 'Čalouněné',
  'Object appearance': 'Vlastní vzhled objektu',
  'Plan style': 'Styl plánku',
  'Edit plan style': 'Upravit styl plánku',
  'Use plan style': 'Použít styl plánku',
  'Follows plan style': 'Řídí se stylem plánku',
  'Local appearance overrides': 'Vlastní vzhled objektu',
  'Styles apply to existing and new objects. Local overrides are preserved.':
      'Styl se použije na stávající i nové objekty. Vlastní vzhled jednotlivých objektů zůstane zachován.',
  'Whole-plan presets': 'Předvolby celého plánku',
  'Object type': 'Typ objektu',
  'Tables': 'Stoly',
  'Chairs': 'Židle',
  'Shapes': 'Tvary',
  'Couches': 'Gauče',
  'Standing areas': 'Plochy ke stání',
  'Fill color': 'Barva výplně',
  'Enter a number from 0 to 1.': 'Zadej číslo od 0 do 1.',
  'Enter a number of at least 1.': 'Zadej číslo alespoň 1.',
  'Enter a non-negative number.': 'Zadej nezáporné číslo.',
  'Unable to apply plan style. Check the values.':
      'Styl plánku se nepodařilo použít. Zkontroluj zadané hodnoty.',

  'Grid': 'Mřížka',
  'Show the grid (G). Grid visibility does not change snapping.':
      'Zobrazit mřížku (G). Její zobrazení nemění přichytávání.',
  'Done': 'Hotovo',
  'Style': 'Styl',
  'Neutral': 'Neutrální',
  'Warm': 'Teplý',
  'Slate': 'Břidlice',
  'Apply style': 'Použít styl',
  'Copy style': 'Kopírovat styl',
  'Paste style': 'Vložit styl',
  'Object color': 'Barva objektu',
  'Outline color': 'Barva obrysu',
  'Text color': 'Barva textu',
  'Seat details': 'Detail místa',
  'Select a seat to view its details.':
      'Kliknutím na místo zobrazíš jeho podrobnosti.',
  'Select a seat to view its details. Drag to pan; scroll to zoom.':
      'Kliknutím zobrazíš detail místa. Tažením posuneš pohled, kolečkem přiblížíš.',
  'Select a table or seat. Shift-click adds to the selection. Drag to pan; scroll to zoom.':
      'Vyber stůl nebo místo. Shift + klik přidá do výběru. Tažením posuneš pohled, kolečkem přiblížíš.',
  'Canvas settings': 'Nastavení plátna',
  'Changes apply immediately. Undo restores the previous style.':
      'Změny se projeví ihned. Zpět obnoví předchozí styl.',

  'Appearance': 'Vzhled',
  'Seat fill #RRGGBBAA': 'Výplň sedadla #RRGGBBAA',
  'Seat color': 'Barva sedadla',
  'Upload background image': 'Nahrát obrázek podkladu',
  'Selected fill #RRGGBBAA': 'Výplň výběru #RRGGBBAA',
  "Preview assembly": "Náhled sestavy",
  "Preview preserves existing seat identities and manual exceptions. Apply commits one change.":
      "Náhled zachová původní sedadla i ruční úpravy. Tlačítko Použít uloží úpravu jako jeden krok.",
  "Left seats": "Sedadel vlevo",
  "Right seats": "Sedadel vpravo",
  "Rear seats": "Sedadel vzadu",
  "Seats per compartment": "Sedadel v kupé",
  "Preview table seats": "Náhled sedadel u stolu",
  "Existing seats keep their identities. Apply is one undo step.":
      "Původní sedadla zůstanou zachována. Celou úpravu vrátíš jednou akcí Zpět.",
  "Enter a valid number.": "Zadej platné číslo.",
  "My object": "Můj objekt",
  "Object name": "Název objektu",
  "Chair": "Židle",
  "Text alignment": "Zarovnání textu",
  "left": "Vlevo",
  "center": "Na střed",
  "right": "Vpravo",
  "Standing capacity": "Kapacita stání",
  "Dotted": "Tečkovaná",
  "Dashed": "Čárkovaná",
  "Solid": "Plná",
  "Outline style": "Styl čáry",
  "Corner radius": "Zaoblení rohů",
  "Vertices [[x,y], ...]": "Body [[x,y], ...]",
  "Paste document fragment JSON": "Vlož JSON objektu",
  "A reusable object can contain at most 2000 nodes.":
      "Vlastní objekt může obsahovat nejvýše 2000 prvků.",
  "Whole canvas": "Celé plátno",
  "Selected polygon": "Vybraný mnohoúhelník",
  "Placement area": "Oblast rozmístění",
  "Requested seats": "Požadovaný počet sedadel",
  "Preview supports 1-500 new seats per batch.":
      "V jednom náhledu lze přidat 1-500 sedadel.",
  "Searching for seat placement": "Hledá se rozmístění sedadel",
  "Placement alternatives": "Varianty rozmístění",
  "No background images loaded. Use your host image import first.":
      "Zatím není načtený žádný podklad. Nejdřív nahraj obrázek.",
  "Keep layout and canvas": "Zachovat rozmístění i plátno",
  "Match image aspect ratio": "Přizpůsobit poměr stran obrázku",
  "Keep background registration": "Zachovat zarovnání podkladu",
  "Choose image": "Vybrat obrázek",
  "Replace image": "Nahradit obrázek",
  "Place background": "Umístit podklad",
  "Fit whole image": "Zobrazit celý obrázek",
  "Fill canvas": "Vyplnit plátno",
  "Transform background": "Upravit podklad",
  "Scale": "Měřítko",
  "Left": "Zleva",
  "Top": "Shora",
  "X": "X",
  "Y": "Y",
  "Rotation": "Úhel",
  "Normalized image coordinates, from 0 to 1. Original pixels are retained.":
      "Souřadnice obrázku jsou v rozsahu 0 až 1. Původní obrazová data se zachovají.",
  "Read only": "Pouze pro čtení",
  "Layout canvas. Select an object, then use arrow keys to move. Shift moves ten steps. Escape cancels.":
      "Plátno plánku. Vyber objekt a posouvej ho šipkami. Se Shiftem se posouvá o deset kroků. Escape zruší akci.",
  "Adjust rows": "Upravit řady",
  "Adjust zigzag": "Upravit cik-cak čáru",
  "Detach seat": "Oddělit sedadlo",
  "Save preset": "Uložit vlastní objekt",
  "Import preset": "Importovat vlastní objekt",
  "Rename preset": "Přejmenovat vlastní objekt",
  "Fit seats": "Rozmístit sedadla",
  "Register background": "Zarovnat podklad",
  "Remove background": "Odstranit podklad",
  "Canvas width": "Šířka plátna",
  "Canvas height": "Výška plátna",
  "Canvas color": "Barva plátna",

  'Dismiss': 'Zavřít',
  'Shape': 'Tvar',
  'Object group': 'Skupina',
  'Seats on couch': 'Místa na gauči',
  'Enter a whole seat count of at least one.':
      'Zadej celé číslo, nejméně jedno místo.',
  'Reserved or blocked seats prevent changing this couch.':
      'Rezervovaná nebo blokovaná místa brání změně počtu míst na gauči.',
  'Reserved or blocked seats prevent changing this seat group.':
      'Rezervovaná nebo blokovaná místa brání změně této skupiny sedadel.',
  'Add bend': 'Přidat zlom',
  'Click start and end, or drag to draw. Shift constrains the angle. Escape cancels.':
      'Klikni na začátek a konec nebo táhni. Shift přichytí úhel, Escape zruší kreslení.',
  'Click to add vertices. Double-click or Enter finishes. Backspace removes the last point.':
      'Klikáním přidávej body. Dvojklik nebo Enter dokončí kresbu, Backspace odebere poslední bod.',

  'Round table. Hold Shift to resize into an ellipse.':
      'Kulatý stůl. Pro změnu na elipsu podrž Shift.',
  'Reserved or blocked seats prevent shrinking this table.':
      'Rezervovaná nebo blokovaná sedadla brání zmenšení tohoto stolu.',
  'Outline #RRGGBBAA': 'Barva čáry #RRGGBBAA',
  'Outline width': 'Tloušťka čáry',
  'Release to attach chair to table.': 'Puštěním připojíš židli ke stolu.',

  'This table has no free chair positions.':
      'U tohoto stolu už není místo pro další židli.',
  'Seat rows': 'Řady sedadel',
  'Number of rows': 'Počet řad',
  'Seats per row': 'Sedadel v řadě',
  'Row arrangement': 'Rozmístění řad',
  'Curvature': 'Zakřivení',
  'Seat spacing': 'Rozestup sedadel',
  'Row spacing': 'Rozestup řad',
  'Blocks': 'Bloky',
  'Aisle width': 'Šířka uličky',
  'Add row': 'Přidat řadu',
  'Remove row': 'Odebrat řadu',
  'Add column': 'Přidat sloupec',
  'Remove column': 'Odebrat sloupec',
  'Add block': 'Přidat blok',
  'Remove block': 'Odebrat blok',
  'Enter a positive whole number.': 'Zadej kladné celé číslo.',

  'Table and seats': 'Stůl a sedadla',
  "Adjust assembly": "Upravit sestavu",
  "Align background with two points": "Zarovnat podklad pomocí dvou bodů",
  "Align using two points": "Zarovnat pomocí dvou bodů",
  "Apply alignment": "Použít zarovnání",
  "Apply preview": "Použít náhled",
  "Bold": "Tučné",
  "Cancel path": "Zrušit kreslení",
  "Choose background image": "Vybrat obrázek podkladu",
  "Copy fragment JSON": "Zkopírovat JSON objektu",
  "Crop image": "Oříznout obrázek",
  "Text is not ready yet.": "Text ještě není připravený.",
  "The selected font could not be loaded.": "Vybraný font se nepodařilo načíst.",
  "Retry font": "Zkusit znovu",
  "Part of the plan could not be displayed.":
      "Část plánku se nepodařilo zobrazit.",
  "Delete preset": "Smazat vlastní objekt",
  "Export fragment": "Exportovat objekt",
  "Finish path": "Dokončit kreslení",
  "Image crop resets. Seats keep their positions. Matching the image ratio expands the canvas without clipping objects.":
      "Ořez obrázku se obnoví. Sedadla zůstanou na místě. Přizpůsobení poměru stran zvětší plátno bez oříznutí objektů.",
  "Import fragment": "Importovat objekt",
  "Import object": "Importovat objekt",
  "Import reusable object": "Importovat vlastní objekt",
  "Italic": "Kurzíva",
  "Physical obstacle": "Fyzická překážka",
  "Preview aligned. Seats have not moved. Tap again to restart a point pair.":
      "Podklad je zarovnaný. Sedadla zůstala na místě. Dalším kliknutím vybereš novou dvojici bodů.",
  "Preview count": "Náhled počtu",
  "Preview placement": "Náhled rozmístění",
  "Remove image": "Odstranit obrázek",
  "Replace background": "Nahradit podklad",
  "Replace the current plan?": "Nahradit současný plánek?",
  "Rotate around corner": "Otáčet kolem rohu",
  "Save object": "Uložit objekt",
  "Save reusable object": "Uložit vlastní objekt",
  "Search incomplete. This is the best result found so far.":
      "Hledání není dokončené. Toto je zatím nejlepší nalezené rozmístění.",
  "Transform image": "Upravit obrázek",
  "Use image": "Použít obrázek",
  "Validate fragment": "Zkontrolovat objekt",

  'Stage': 'Pódium',
  'Dance floor': 'Taneční parket',
  'Entrance': 'Vstup',
  'Ground floor': 'Přízemí',
  'Balcony': 'Balkon',
  'Stairs': 'Schody',
  'Standing area': 'Místa ke stání',
  'Driver': 'Řidič',
  'Corridor': 'Chodba',
  'Service area': 'Zázemí',
  'Door': 'Dveře',
  'Carriage': 'Vagón',
  'Compartment': 'Kupé',
  'Your text': 'Tvůj text',

  'Objects stay in place. To move an object that fills the canvas, increase Width or Height first.':
      'Objekty zůstanou na místě. Pokud objekt vyplňuje celé plátno, před přesunem nejprve zvětši šířku nebo výšku plátna.',
  'Schematic size. No physical measurements required.':
      'Rozměry jsou orientační. Nemusíš znát skutečné rozměry sálu.',
  'Canvas selected. Drag an edge or corner to resize. Escape exits.':
      'Vybrané plátno. Velikost upravíš tažením hrany nebo rohu. Escape ukončí úpravy.',
  'Unable to copy selection to the clipboard.':
      'Výběr se nepodařilo zkopírovat do schránky.',
  'Clipboard does not contain a valid layout selection, or access was denied.':
      'Schránka neobsahuje platné objekty plánku nebo prohlížeč nepovolil přístup.',
  'Table capacity exceeded': 'Počet míst přesahuje kapacitu stolu.',
  'Target table is outside the canvas': 'Stůl je mimo plátno.',
  'Fixed chairs prevent a collision-free table layout':
      'Kvůli pevným židlím nelze sedadla rozmístit bez překrývání.',
  'No collision-free chair position is available':
      'Pro židli tu není volné místo bez překrývání.',
  'Canvas would clip objects': 'Zmenšení plátna by ořízlo objekty.',
  'Locked target table': 'Cílový stůl je zamčený.',
  'Locked transport layout': 'Dopravní sestava je zamčená.',
  'Dimensions must be finite and positive':
      'Rozměry musí být kladná konečná čísla.',
  'Couch dimensions must be finite and positive':
      'Rozměry gauče musí být kladná konečná čísla.',
  'Cannot place here': 'Sem nelze umístit',
  'Not enough room here. Move the object to a free area.':
      'Tady není dost místa. Přesuň objekt na volnou plochu.',
  'Object must stay inside the canvas. Enlarge the canvas first.':
      'Objekt musí zůstat uvnitř plátna. Nejdřív zvětši plátno.',
  'Foreground': 'Popředí',
  'Background': 'Pozadí',
  'Swap colors': 'Prohodit barvy',
  'Set color': 'Nastavit barvu',
  'RGB hex': 'Barva HEX',
  'Enter six RGB hex digits.': 'Zadej šest znaků barvy HEX.',
  'Opacity': 'Krytí',
  'Used colors': 'Použité barvy',
  'From artwork': 'Z podkladu',
  'Basic colors': 'Základní barvy',
  'Typography': 'Písmo',
  'Default font': 'Výchozí písmo',
  'Font not found': 'Písmo nenalezeno',
  'Could not load font': 'Písmo se nepodařilo načíst',
  'Reset to default': 'Obnovit výchozí',
  'Font name': 'Název písma',
  'Search fonts': 'Hledat písma',
  'Objects': 'Objekty',
  'Detach from assembly': 'Oddělit ze sestavy',
  'Reset angle': 'Vyrovnat rotaci',
  'Lock object': 'Zamknout objekt',
  'Advanced object properties': 'Další vlastnosti objektu',
  'Rotate handle': 'Táhlo rotace',
  'Resize handle': 'Táhlo velikosti',
  'Couch': 'Gauč',
  'Properties': 'Vlastnosti',
  'Selection': 'Výběr',
  'Apply text to other tables': 'Použít text pro ostatní stoly',
  'Apply text to other seats': 'Použít text pro ostatní sedadla',
  'Apply text to other texts': 'Použít styl pro ostatní texty',
  'Apply text to matching objects': 'Použít text pro objekty stejného typu',
  'Copy font, size, weight, alignment and text color':
      'Přenese písmo, velikost, řez, zarovnání a barvu textu. Zamčené objekty vynechá.',
  'Text style applied': 'Styl textu přenesen',
  'seat': 'Židle',
  'table': 'Stůl',
  'shape': 'Tvar',
  'text': 'Text',
  'furniture': 'Nábytek',
  'capacityArea': 'Stání',
  'group': 'Skupina',
  'Drag onto the plan, or click to place':
      'Přetáhni do sálu nebo vyber a klikni do plánku',
  'Seating': 'Sezení',
  'Paint a connected surface.': 'Namaluj souvislou plochu.',
  'Surface brush limit reached.': 'Plocha dosáhla maximální velikosti.',
  'Paint inside the canvas.': 'Maluj uvnitř plátna.',
  'Baggage': 'Zavazadla',
  'Vestibule': 'Nástup',
  'Boxes': 'Lóže',
  'Orchestra pit': 'Orchestřiště',
  'Premium seats': 'Prémiové sezení',
  'Cross aisle': 'Příčná ulička',
  'Two carriages, nine six-seat compartments each':
      'Dva vozy, každý s devíti šestimístnými kupé',
  'Continuous curved stalls, side boxes and balcony':
      'Souvislé obloukové řady, boční lóže a balkón',
  'Continuous rows, side access and a cross aisle':
      'Souvislé řady, boční přístupy a příčná ulička',
  'Drag across cells to join table modules. One cell is a table for 4. Release finishes. Escape cancels.':
      'Tažením přes buňky spojíte moduly stolu. Jedna buňka odpovídá stolu pro 4. Puštěním dokončíte, Escape zruší.',
  'Narrow bar modules': 'Úzké moduly baru',
  'Drag to join narrow bar modules. Release finishes. Escape cancels.':
      'Tažením spojíte úzké moduly baru. Puštěním dokončíte, Escape zruší.',
  'One cell = one table for 4': 'Jedna buňka = stůl pro 4',
  'Paint bar': 'Malovat bar',
  'Paint table': 'Malovat stůl',
  'Draw table': 'Načrtnout stůl',
  'Draw bar': 'Načrtnout bar',
  'Surface footprint': 'Půdorys plochy',
  'Table shape': 'Tvar stolu',
  'Surface shape': 'Tvar plochy',
  'Custom outline': 'Vlastní obrys',
  'Current outline': 'Současný obrys',
  'The current outline is preserved until you choose a new shape.':
      'Současný obrys zůstane zachován, dokud nevybereš nový tvar.',
  'Blocks seat placement': 'Brání umístění židlí',
  'Change table shape': 'Změnit tvar stolu',
  'The selected shape cannot fit the existing chairs. Increase the table size first.':
      'Zvolený tvar nepojme současné židle. Nejprve zvětšete stůl.',
  'Edit outline': 'Upravit obrys',
  'Extend surface': 'Vytáhnout rameno',
  'Reshape surface': 'Upravit půdorys',
  'Pull an edge handle to extend the surface.':
      'Tažením úchytu na hraně prodloužíš nebo zkrátíš rameno.',
  'Pull an edge handle to extend the surface. Drag corners to reshape it.':
      'Tažením úchytu na hraně vytáhneš nové rameno. Rohy upravíš tažením bodů.',
  'Use as table': 'Použít jako stůl',
  'Use as bar': 'Použít jako bar',
  'Create surface': 'Vytvořit plochu',
  'Surface width': 'Šířka plochy',
  'Narrower surface': 'Zúžit plochu',
  'Wider surface': 'Rozšířit plochu',
  'Click along the surface center. Enter finishes; Escape cancels. Pull edge handles to add branches.':
      'Klikáním načrtni střed plochy. Enter dokončí, Escape zruší. Úchyty hran vytáhnou další ramena.',
  'The surface outline cannot cross itself.': 'Obrys plochy se nesmí křížit.',
  'Contoured seats, headrests and armrests.':
      'Tvarovaná sedadla, opěrky hlavy a područky.',
  'Gala ball': 'Slavnostní ples',
  'Contemporary ball': 'Moderní ples',
  'Timber banquet, central dance floor, stage and bar':
      'Dřevěný banket, centrální parket, pódium a bar',
  'Lounge round tables, reception and dance floor':
      'Kulaté stoly v lounge stylu, recepce a taneční parket',
  'Mixed seating, generous aisles and a central dance floor':
      'Smíšené sezení, široké průchody a centrální parket',
  'Cinema': 'Kinosál',
  'Theatre': 'Divadlo',
  'Screen, two seating blocks, aisles and exits':
      'Plátno, dva bloky sezení, uličky a východy',
  'Curved stalls, balcony, proscenium and backstage':
      'Obloukové hlediště, balkón, jeviště a zákulisí',
  'Conference and reception': 'Konference a recepce',
  'Stage, audience, meeting tables and lounge with a U-shaped bar':
      'Pódium, hlediště, jednací stoly a lounge s barem do U',
  'Two decks, stairs, service area and separate seating':
      'Dvě podlaží, schody, zázemí a samostatné sezení',
  'Reception': 'Recepce',
  'Screen': 'Promítací plátno',
  'Exit': 'Východ',
  'Backstage': 'Zákulisí',
  'Stalls': 'Přízemní hlediště',
  'Conference': 'Konference',
  'Meeting area': 'Jednací část',
  'Geometry': 'Rozměry a poloha',
  'Floor appearance': 'Vzhled podlahy',
  'Floor patterns stay visible when zoomed out. A custom background takes precedence.':
      'Vzor zůstává viditelný i při oddálení. Vlastní obrázek podkladu má přednost.',
  'Plain floor': 'Bez vzoru',
  'Wooden floor': 'Dřevěná podlaha',
  'Tiled floor': 'Dlažba',
  'Carpet': 'Koberec',
  'Double-decker bus': 'Dvoupatrový autobus',
  'Decks': 'Počet podlaží',
  'Lower deck': 'Dolní podlaží',
  'Upper deck': 'Horní podlaží',
  'Seat layout': 'Uspořádání sedadel',
  'Add one row': 'Přidat řadu',
  'Remove one row': 'Odebrat řadu',
  'Rows on lower deck': 'Řady v dolním podlaží',
  'Rows on upper deck': 'Řady v horním podlaží',
  'Rear seats on lower deck': 'Zadní sedadla v dolním podlaží',
  'Rear seats on upper deck': 'Zadní sedadla v horním podlaží',
  'Add compartment': 'Přidat kupé',
  'Remove compartment': 'Odebrat kupé',
  'Add one': 'Přidat',
  'Remove one': 'Odebrat',
  'Manual or protected seats prevent changing this transport layout.':
      'Sestavu nelze změnit, protože by se odebrala ručně upravená, rezervovaná nebo blokovaná sedadla.',
  'Atomic seat groups prevent changing this transport layout.':
      'Sestavu nelze změnit, protože by se rozdělila nedělitelná skupina sedadel.',
  'Transport': 'Doprava',
  'Text & shapes': 'Text a tvary',
  'Seat': 'Židle',
  'Table': 'Stůl',
  'Round table': 'Kulatý stůl',
  'Rows': 'Řady sedadel',
  'Arc': 'Oblouková řada',
  'Lounge': 'Lounge',
  'Bus': 'Autobus',
  'Compartments': 'Kupé',
  'Standing': 'Stání',
  'Text': 'Text',
  'Rectangle': 'Obdélník',
  'Ellipse': 'Elipsa',
  'Line': 'Čára',
  'Arrow': 'Šipka',
  'Zigzag': 'Cik-cak čára',
  'Remove one tooth': 'Odebrat jeden zub',
  'Add one tooth': 'Přidat jeden zub',
  'Number of teeth': 'Počet zubů',
  'Zigzag height': 'Výška zubů',
  'Line endpoint handle': 'Koncový bod čáry',
  'Zigzag height handle': 'Táhlo výšky zubů',
  'Enter a whole number from 1 to 255.': 'Zadejte celé číslo od 1 do 255.',
  'Polyline': 'Lomená čára',
  'Polygon': 'Mnohoúhelník',
  'No matching objects. Try another name.':
      'Nic jsme nenašli. Zkus jiný název.',
  'Find object': 'Hledat objekt',
  'Find layer': 'Hledat ve vrstvách',
  'Undo': 'Zpět',
  'Redo': 'Znovu',
  'Insert': 'Vložit',
  'Select': 'Výběr',
  'Pan': 'Posun plátna',
  'Resize': 'Velikost',
  'Rotate': 'Rotace',
  'Snap': 'Přichytávání',
  'Snap to objects, 8-unit grid and 15° angles. Hold Alt to bypass.':
      'Přichytávat k objektům, mřížce a úhlům po 15°. Alt dočasně vypne přichytávání.',
  'Drag to rotate. Snap: 15°. Hold Alt for free rotation.':
      'Tažením otáčej po 15°. S Alt otáčej volně.',
  'Drag selected object to resize. Shift preserves proportions.':
      'Tažením měň velikost. Shift zachová poměr stran.',
  'Drag to pan. Pinch or scroll to zoom.':
      'Tažením posouvej plátno. Kolečkem přibližuj.',
  'Choose template': 'Šablony sálů',
  'Choose a starting plan': 'Vyber výchozí sál',
  'Every layout is editable. All sections stay on one plan.':
      'Každý sál můžeš upravit. Všechny části zůstávají v jednom plánku.',
  'Close gallery': 'Zavřít šablony',
  'Replace plan': 'Použít šablonu',
  'Classic ball': 'Klasický ples',
  'Round tables': 'Kulaté stoly',
  'Mixed ball': 'Smíšený ples',
  'Hall with balcony': 'Sál s balkónem',
  'Lounge and standing': 'Lounge a stání',
  'Auditorium': 'Řadový sál',
  'Two train carriages': 'Dva vlakové vozy',
  'Blank layout': 'Prázdný sál',
  'Start with an empty canvas': 'Začni s čistým plátnem',
  '12 tables, dance floor and stage': '12 stolů, taneční parket a pódium',
  '10 round tables, dance floor and stage':
      '10 kulatých stolů, parket a pódium',
  '6 rectangular and 4 round tables': '6 obdélníkových a 4 kulaté stoly',
  'Ground floor and balcony in one plan': 'Přízemí a balkón v jednom plánku',
  'Six two-seat couches and a standing area':
      'Šest dvoumístných gaučů a plocha ke stání',
  'Ten rows with a central aisle': 'Deset řad se středovou uličkou',
  'Ten 2+2 rows and five rear seats': 'Deset řad 2 + 2 a pět zadních sedadel',
  'Two carriages, four six-seat compartments each':
      'Dva vozy, každý se čtyřmi šestimístnými kupé',
  'Fit plan': 'Celý plánek',
  'Zoom in': 'Přiblížit',
  'Zoom out': 'Oddálit',
  'Properties and layers': 'Vlastnosti a vrstvy',
  'Canvas': 'Plátno',
  'Background image': 'Podklad',
  'Reusable objects': 'Vlastní objekty',
  'Fit new seats': 'Doplnit sedadla',
  'Layers': 'Vrstvy',
  'Saved': 'Uloženo',
  'Unsaved changes': 'Neuložené změny',
  'Name': 'Název',
  'Width': 'Šířka',
  'Height': 'Výška',
  'Rotation °': 'Úhel °',
  'Position X': 'Pozice X',
  'Position Y': 'Pozice Y',
  'Fill #RRGGBBAA': 'Výplň #RRGGBBAA',
  'Stroke #RRGGBBAA': 'Obrys #RRGGBBAA',
  'Text color #RRGGBBAA': 'Barva textu #RRGGBBAA',
  'Stroke width': 'Tloušťka obrysu',
  'Font size': 'Velikost písma',
  'Line height': 'Řádkování',
  'Duplicate': 'Duplikovat',
  'Delete': 'Smazat',
  'Group': 'Seskupit',
  'Ungroup': 'Zrušit skupinu',
  'Split into seats': 'Rozdělit na sedadla',
  'Select this seat': 'Vybrat toto sedadlo',
  'Lock': 'Zamknout',
  'Unlock': 'Odemknout',
  'Bring to front': 'Přenést dopředu',
  'Bring forward': 'O vrstvu výš',
  'Send backward': 'O vrstvu níž',
  'Send to back': 'Přenést dozadu',
  'Align left': 'Zarovnat vlevo',
  'Align right': 'Zarovnat vpravo',
  'Align top': 'Zarovnat nahoru',
  'Align bottom': 'Zarovnat dolů',
  'Distribute horizontally': 'Rozmístit vodorovně',
  'Distribute vertically': 'Rozmístit svisle',
  'Add one seat': 'Přidat židli',
  'Remove one seat': 'Odebrat židli',
  'Rotate left 90 degrees': 'Otočit doleva o 90°',
  'Rotate right 90 degrees': 'Otočit doprava o 90°',
  'Reset rotation': 'Vyrovnat rotaci',
  'Apply': 'Použít',
  'Cancel': 'Zrušit',
  'Close': 'Zavřít',
  'Confirm': 'Potvrdit',
  'Customer preview': 'Náhled pro návštěvníka',
  'Return to editor': 'Zpět do editoru',
  'Save local baseline': 'Uložit plánek',
  'Files and diagnostics': 'Soubory a další možnosti',
  'Import background image': 'Nahrát podklad',
  'Export portable demo': 'Exportovat plánek včetně podkladů',
  'Export geometry only': 'Exportovat pouze geometrii',
  'Import portable demo': 'Otevřít plánek ze souboru',
  'Reset template': 'Obnovit výchozí šablonu',
  'Diagnostics': 'Diagnostika dema',
  'Recovered local draft': 'Obnovený rozpracovaný plánek',
  'Demo - sample data': 'Připravený ukázkový sál',
  'Draft saved on this device': 'Změny uložené v tomto prohlížeči',
  'Portable demo exported': 'Plánek exportovaný včetně podkladů',
  'Geometry exported without demo prices or states':
      'Geometrie exportovaná bez cen a rezervací',
  'Imported portable draft': 'Plánek načtený ze souboru',
  'Keep editing': 'Pokračovat v úpravách',
  'Replace': 'Nahradit',
  'Replace unsaved draft?': 'Nahradit rozpracovaný plánek?',
  'Save or export first to keep your changes.':
      'Pro zachování změn nejdřív plánek ulož nebo exportuj.',
  'Accessible seat list': 'Seznam míst',
  'Choose seats or standing places': 'Vyber místo nebo stání',
  'Confirm quantity': 'Potvrdit počet',
  'Quantity updated.': 'Počet upravený.',
  'Select an object to edit its properties.':
      'Vyber objekt v sále a uprav jeho vlastnosti.',
  'Select an object on the plan or in Layers to edit it.':
      'Vyber objekt v sále nebo ve vrstvách. Tady upravíš jeho vlastnosti.',
  'Set canvas size': 'Rozměry plátna',
  'Canvas size': 'Rozměry plátna',
  'Fit canvas to content': 'Přizpůsobit plátno obsahu',
  'Background #RRGGBBAA': 'Barva plátna #RRGGBBAA',
  'Objects keep their positions. A smaller canvas cannot hide seats.':
      'Objekty zůstanou na svých místech. Menší plátno nesmí skrýt sedadla.',
  'Align and distribute': 'Zarovnání a rozmístění',
  'Center horizontally': 'Vystředit vodorovně',
  'Center vertically': 'Vystředit svisle',
  'Save as object': 'Uložit jako vlastní objekt',
  'Choose color': 'Vybrat barvu',
  'Color': 'Barva',
  'Custom color': 'Vlastní barva',
  'Custom color #RRGGBBAA': 'Vlastní barva #RRGGBBAA',
  'Last two digits set opacity: 00-FF':
      'Poslední dvě číslice určují krytí: 00-FF',
  'Use #RRGGBBAA including opacity.': 'Zadej #RRGGBBAA včetně krytí.',
  'Transparent': 'Průhledná',
  'Font': 'Písmo',
};
