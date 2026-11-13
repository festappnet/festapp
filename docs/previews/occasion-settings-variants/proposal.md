# Nastavení celé akce - porovnání návrhů

Pouze návrh uspořádání, bez změny aplikace. `index.html` funguje přímo z disku; volby Počítač a Telefon mění skutečnou šířku vnořeného náhledu. Prohlédněte každou variantu v obou velikostech a otevřete Vzhled a viditelnost, Funkce a Pokročilé. Ukázkové hodnoty nejsou skutečná data akce.

## Tři strukturální možnosti

| Varianta | Široký počítač | Telefon | Hlavní kompromis |
| --- | --- | --- | --- |
| A - Sekce a náhled | Navigace oblastí, jeden editor, náhled vedle obrázku a popisu | Kompaktní volba čtyř oblastí, jeden editor, rozbalovací náhled | Rychlé opakované úpravy; nutnost zachovat draft při přepínání |
| B - Jeden dokument | Souvislé sekce, kompaktní orientace nahoře bez dalšího postranního panelu, vzhled ve dvou sloupcích | Svislé rozbalovací kapitoly, více může zůstat otevřených | Snadná celková kontrola; s mnoha funkcemi dlouhý dokument |
| C - Přehled a detail | Čitelné souhrny hodnot vlevo a zvolený editor vpravo | Přehled jako vlastní obrazovka, detail se zpětnou navigací | Dobrá orientace občasného správce; více kroků a údržba souhrnů |

Doporučuji B. Udržuje veřejný obsah akce pohromadě, podrobnosti funkcí odkrývá postupně a nejméně ohrožuje stávající společný draft. Na široké ploše využívá druhý sloupec pro náhled; na telefonu mění dokument na svislé rozbalovací kapitoly. A dává smysl při převaze opakovaných cílených úprav, C při převaze občasných správců. Pro výběr B není potřeba přebírat postranní osnovu z editoru formuláře. Všechny varianty zachovávají světlou administrační plochu a tmavomodrou hlavičku. Nejde o nový vizuální styl ani o návrh nastavení konkrétního formuláře.

## Co se musí zachovat

Zdroj: `origin/main` na `94012d26da25395717882222b430154674587743`. Zkoumány `occasion_settings_tab.dart`, `occasion_advanced_settings.dart`, `occasion_features_section.dart`, `occasion_settings_strings.dart`, `feature_form.dart`, `feature_settings_editor.dart`, `feature_metadata.dart`, `feature_service.dart` a `form_feature.dart`.

- Název, začátek a konec včetně času, místo, obrázek a jeho stávající výběr/ořez/odebrání, formátovaný HTML popis. Náhled karty je návrhová prezentační pomůcka; případná implementace má použít existující `OccasionCard`, nikoli nový model dat.
- Veřejnost detailů akce, skrytí v seznamech a propagace jsou oddělené volby. Propagace vyžaduje obrázek; odebrání obrázku ji vypíná ve draftu. Dostupnost formuláře je samostatná oblast a není přepínačem veřejnosti akce.
- Odkaz akce, historie a práce s uloženým odkazem, e-mail pro odpovědi s výchozí hodnotou pořadatele, časové pásmo. V návrhu se časové pásmo přesouvá z pokročilých voleb přímo k termínu jako rozbalovací detail; jde jen o umístění stejného pole. Odkaz a veřejnost akce závisejí na `AppConfig.isAppSupported`.
- Funkce musí zůstat hledatelné podle názvu i popisu, rozdělené na zapnuté a ostatní. Ukázka hledá jen zobrazené názvy; produkční vyhledávání se nemá omezit. Seznam vzniká ze skutečných funkcí akce a konfigurace tenantu, nikoli z pevného seznamu ukázky.
- Všechny existující specializované editory zůstávají: formulář, vstupenka, doprovod, smlouva, poradenství, záloha, import, mapa, program, pobyt a workshopy. Jednoduché funkce si ponechávají zapnutí/vypnutí. Formulář může být povinně zapnutý ve variantě bez podpory aplikace. Platební splatnost a připomínky patří stávajícímu editoru funkce Formulář, nejsou novou globální platební sekcí.
- Jedna persistentní lišta Uložit / Zahodit a původní `EditorSnapshot`, `EditorDraftScope`, `HtmlSaveCoordinator`. Přepnutí sekce není uložení, opuštění nebo reset draftu. Vzhled vstupenky zachovává samostatný `onSaveTicket` a `TicketLayoutSaver` včetně konfliktů; nelze jej převést na druhý obecný autosave.
- Smazání jen s odpovídající capability, se stávajícím potvrzením a zákazem při jakýchkoli objednávkách včetně stornovaných. Read-only, ukládání, načítání, validační a konfliktní stavy musí být zachovány. Ukázka negeneruje nové oprávnění ani nové demo chování.

## Implementační rizika pro následné rozhodnutí

A a C nesmějí odmountovat ztrátový editor nebo duplikovat datovou autoritu. B musí při validaci otevřít kapitolu s chybou a přesunout fokus. C potřebuje souhrny odvozené z téhož draftu. Všechny varianty musí udržet dostupnou dolní lištu při mobilní klávesnici a respektovat pořadí fokusu. Na telefonu nejsou skryté navigační prvky ponechané ve fokusovatelné vrstvě; žádná varianta nepoužívá vodorovný posun stránky.

Ukázka záměrně nenapodobuje celý HTML editor, upload, ticket designer nebo serverové validace. Jejich místo a vlastník jsou uvedeny, skutečné editory mají být znovu použity. Pro veřejné odkazy, platby, práva a ukládání se tímto návrhem nemění kontrakty.

## Srovnání se zavedenými produkty

Srovnání vychází z oficiální dokumentace dohledané v rámci této úlohy. Nejde o pixelové napodobení jejich přihlášených aplikací.

- [Eventbrite: tvorba akce](https://www.eventbrite.com/help/en-us/articles/551351/how-to-create-an-event/) sdružuje název, souhrn, obrázek, termín, místo a přehled; publikování obsahuje soukromí, dohledatelnost a náhled. [Organizer pro Android](https://www.eventbrite.com/help/en-au/articles/644972/how-to-use-the-eventbrite-organizer-app-for-android/) dokumentuje mobilní práci se základními údaji, místem, termínem, obrázkem, soukromím a popisem. **Odvození pro Festapp:** souvislá prezentace akce, viditelný náhled a srozumitelné důsledky viditelnosti. Jejich samostatné publikování se nepřebírá.
- [Ticket Tailor: čekací listina](https://help.tickettailor.com/en/articles/2748053-how-to-set-up-a-waitlist-for-your-event) používá pokročilé nastavení a odhalení podmínek po zapnutí. [Poplatky](https://help.tickettailor.com/en/articles/5210356-how-to-pass-fees-onto-your-ticket-buyers) rozlišují výchozí hodnoty a explicitní změnu pro akci. **Odvození:** postupné rozbalování funkcí a jasné vysvětlení zděděného e-mailu pro odpovědi. Poplatky ani čekací listina se tímto nepřidávají do Festapp nastavení akce.
- [Shopify: formuláře](https://shopify.dev/docs/apps/design/user-experience/forms) doporučuje pojmenované sekce, kontextovou společnou lištu Uložit / Zahodit a samostatnou stránku pro velké formuláře. **Odvození:** varianta B je vyhrazená pracovní plocha, nepoužívá modal ani samostatné ukládání každé sekce.
- [GitHub: smazání repozitáře](https://docs.github.com/en/repositories/creating-and-managing-repositories/deleting-a-repository) umisťuje nevratné operace do spodní Danger Zone. [Eventbrite: smazání akce](https://www.eventbrite.com/help/en-ie/articles/172435/how-to-delete-an-event/) odlišuje smazání a zrušení zveřejnění s podmínkami. **Odvození:** oddělené smazání s existujícími Festapp právy a objednávkovým omezením, bez nových potvrzovacích pravidel.

Mobilní struktury A/B/C jsou vlastní návrhy; dokumentace nepotvrzuje, že referenční produkty používají přesně tyto navigační kompozice. Finální preference je návrhový úsudek pro současný rozsah Festapp, nikoli důkaz uživatelským testováním.

## Rozpracovaná varianta B s mřížkou funkcí

Soubor: `variant-b-refined.html`. Pro přímé otevření sekce funkcí použijte `variant-b-refined.html#features`. Horní přepínač Telefon nastaví skutečný viewport 390 px; při změně šířky se otevřený editor přesune pod odpovídající řádek bez ztráty jeho místních hodnot.

- Mřížka patří pouze do katalogu funkcí. Zbytek stránky zůstává souvislým dokumentem: kompaktní dvousloupcové základní údaje, časové pásmo u termínu, obrázek a popis vedle náhledu, tři nezávislé volby viditelnosti, pokročilé údaje a oddělené smazání.
- Počítač používá tři sloupce funkcí, střední šířka dva a telefon jeden. Dlaždice obsahuje ikonu, název, konkrétní účel, textový stav a samostatné tlačítko Nastavit. Není zde souběh skrytého zapnutí při kliknutí na celou dlaždici. Zapnutí se mění explicitně uvnitř editoru.
- Editor je vložen přes celou šířku mřížky pod řádek vybrané funkce. Formulář a vstupenka tak dostanou prostor pro dvě logické skupiny na počítači; telefon je skládá svisle. Zavřít nastavení a Zpět na přehled vracejí fokus k funkci. Nepoužívá se modal, boční vysouvání ani vodorovné animace.
- Místní stav editoru přežívá zavření, otevření jiné funkce i filtrování. Vyhledávání zahrnuje název a účel; při hledání se dostupné funkce rozbalí. Prázdný výsledek nabízí vymazání hledání. Skupiny Zapnuté a Další vycházejí ze skutečného místního stavu; žádná další pevná produktová taxonomie se nezavádí.
- Formulář konkretizuje existující externí odkaz/cenu, interní režim splatnosti a počet dní, připomínky a interval, text tlačítka. Přesné validační a přepínací chování zůstává vlastnictvím existujícího editoru; prototyp není jeho náhradou. Stávající zdroj při změně externího režimu pracuje s controllery jinak než tento neperzistentní návrh.
- Vstupenka konkretizuje existující volbu doručení, mobilní peněženku a její vzhled, předgenerované vstupenky, oprávněný vstup do nastavení kontroly, PDF rozložení a náhled doručovacího e-mailu. Přesné režimy doručení a wallet readiness jsou záměrně ponechány stávajícím komponentám. Zdroj `TicketSettings` v tomto průchodu neobsahoval pole pro dávkové limity, proto se takové nastavení nevymýšlí.
- Pro přehlednost je rozpracován Formulář, Vstupenka a ukázka Zálohy; ostatní specializované editory mají označené místo plné šířky. V implementaci se vloží existující editory v úplnosti. Jednoduché funkce zůstávají přepínači bez vymyšlených polí.

Doplněná cílená kontrola zdrojů: `features/editors/form_feature_editor.dart`, `ticket_layout/views/ticket_settings.dart`, `features/editors/deposit_feature_editor.dart` na stejném `origin/main`. Žádné změny aplikačního kódu, databáze, buildů nebo publikování.

### Zbývající hranice návrhu

Toto je zkoušitelný návrh rozložení, nikoli náhradní implementace business pravidel. Uložit výslovně oznamuje, že nic neuložilo na server; Zahodit obnoví místní náhled. Stávající HTML editor, výběr obrázku, potvrzení smazání, validace, skutečný ticket designer, readiness peněženky, read-only/loading/conflict stavy a oprávnění nejsou nově implementovány. Produkční přesun nesmí ztratit společný draft, aktivní HTML editor ani samostatný vlastník uložení ticket layoutu. Rozšířený katalog ukazuje app-supported variantu; tenant bez podpory aplikace má filtrovaný seznam a případně nevypínatelnou funkci Formulář.
