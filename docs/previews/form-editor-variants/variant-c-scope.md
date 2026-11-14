# Varianta C - rozsah dopracovaného náhledu

Požadavek: zachovat editovatelný úvod, na širokém displeji zobrazit osnovu obsahu, na mobilu ji skrýt. Osnova od 1100 CSS px je návrhový breakpoint, nikoli změna limitů aplikace. Úvod i všechna pole zůstávají v jednom souvislém editoru.

Statická ukázka: `variant-c.html`. Nejde o implementaci Flutter editoru. Pokročilé kontroly a některé vedlejší akce jsou označené jako ilustrační. Původní porovnání A/B/C zůstává v `index.html`.

## Zachování funkcí při budoucí implementaci

- `form_tab.dart`: čtyři současné záložky, výběr formuláře, vytvoření/kopírování a ochrana konceptu při navigaci.
- `form_editor_content.dart`: plnohodnotný úvodní HTML editor včetně médií; oba náhledy uložené verze; volba uložit/zobrazit uložené/pokračovat při změnách; explicitní uložit/zahodit. Celý stávající blok Dostupnost / Kapacita a náhradníci / Rozvrh a limity / Obsah zavřeného formuláře zůstává na svém místě nad úvodem. Nezmenšovat na stavový řádek, neskrývat celý blok a nepřesouvat jej do jiné záložky. Zachovat současná vnitřní rozbalení a původní komponenty i vlastníka ukládání.
- `form_fields_generator.dart`: všechny dosavadní typy a omezení jejich dostupnosti, pořadí přetažením, názvy, popisy, povinnost a viditelnost; nastavení konkrétních typů; pravidla a důvody blokovaného odstranění. Osnova jen naviguje, nenahrazuje samotné bloky. Ukázka nabízí i posun přes nabídku; přetažení ve statické ukázce není implementováno.
- Vstupenky a produkty: maximum kusů na objednávku, vlastní editor produktů/cen a jejich detailů, skupiny a jejich povinnost/viditelnost/vícenásobný výběr, přidání nového produktu a typu, připojení existující skupiny, výběr míst, poznámka i podmíněné informace o záloze.
- `form_capacity_settings.dart`: kapacita, počty obsazených/nabídnutých míst, zbývající kapacita, náhradníci a délka nabídky; odlišné chování pro plánek a existující aktivní rezervace.
- `form_unavailable_content_editor.dart` a `presale_content_editor.dart`: obsah před otevřením a po uzavření; rich HTML a správa bloků, sběr e-mailů a upozornění na otevření, nastavení záhlaví, odpočet, mobilní zobrazení a podmíněná obnova archivu. Zachovat neuložené změny obou panelů při přepínání.
- `form_settings_content.dart`: název, veřejný odkaz a jeho historie/sdílení; upomínky a interval; splatnost (dědění/vlastní/bez); bankovní převod a příjemce/účet/stav, hotovost s pokyny a dostupní poskytovatelé online plateb; číslování a variabilní symbol; zpráva pro příjemce; měření a jeho stavy; tón komunikace; chráněné odstranění formuláře. Zachovat současnou samostatnou správu konceptu tohoto editoru.
- `form_design_content.dart`, `form_design_settings.dart`, `form_responses_content.dart`: stávající vzhled/barvy/písmo/režim/vložení/karty a dosavadní správa odpovědí zůstávají samostatné, bez omezení.
- Všude zachovat capability kontroly, režim pouze pro čtení, podmíněné funkce a omezení dat. Statická ukázka neslouží jako nový datový nebo autorizační kontrakt.

Astra Medium provedla kontrolu seznamu zachovávaných funkcí proti současným zdrojům. Náhled pouze mění hierarchii a umístění akcí; finální implementace musí znovu použít stávající editory a pravidla, nikoli je nahradit zjednodušenými HTML ovládacími prvky ukázky.
