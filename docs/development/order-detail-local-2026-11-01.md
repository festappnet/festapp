# Detail objednávky v lokální aplikaci

Vybraná varianta A používá panel vedle tabulky, pokud pro tabulku zbývá čitelná
šířka. V menším okně zabere detail pracovní plochu. Jedno kliknutí vybírá buňku; detail otevírá
dvojklik na needitovatelnou datovou buňku nebo tlačítko s číslem objednávky.
Celý řádek otevřené objednávky má trvalé orámování nezávislé na aktivní buňce.
Checkbox dál vybírá hromadné akce; kopírování čísla
objednávky neotevírá detail. Tabulka si ponechává filtry, řazení i rozpracovanou
interní poznámku a tlačítka Uložit/Zahodit.

Hranici tabulky a detailu lze táhnout nebo ovládat šipkami klávesnice. Šířka
detailu má meze 360-760 px a tabulka nejméně 480 px. Volba se ukládá pouze
v prohlížeči na tomto počítači, nikoli do účtu nebo databáze; mobilní šířka
ji nepřepisuje. Zavření je vpravo nahoře; samostatné zvětšení bylo na přání odstraněno.

Přehled obsahuje kontakt, finanční souhrn, relevantní zprávu, objednané produkty
a oddělené poznámky. Produkty se upravují stávajícím produktovým dialogem
příslušné vstupenky či přihlášky. Jediná přihláška na objednávku má společný
obsah bez opakované hlavičky; více přihlášek a vstupenek je rozděleno po osobách.
Stav objednávky má barvu podle dosavadního stavového modelu a počty mají české
i anglické tvary. Jediný dostupný plánek se načte automaticky bez přepínače.
Vstupenky a místa propojují konkrétní vstupy, objednané produkty, vlastní odpovědi
a uložený plánek. Platby ukazují skutečné pohyby přes dosavadní platební obsah.
E-maily zachovávají původní příjemce a detaily pokusů. Historie používá skutečné
snapshoty a porovnává také změnu e-mailu. Neuložený kontakt je společný pro
Přehled a E-maily.

Uložit kontakt nic neposílá. Výslovné odeslání vytváří požadavek v kanonické
frontě, jehož přijetí není doručením. Při přerušené odpovědi lze ověřit původní
požadavek pod jeho původním identifikátorem. Zrušení objednávky nebo vstupenky
samo nevrací platbu. Plánek představuje současnou uloženou geometrii, nikoli
historickou rekonstrukci ani rozepsaný editor.

## Význam všech 27 e-mailových položek

Položky patří různým vrstvám. Nejde o jednu posloupnost stavů objednávky.
Aktuální problém a dostupné odeslání určuje server, nikoli poslední barevný štítek.

| Klíč | Význam |
| --- | --- |
| `unavailable` | Pro tuto zprávu není dostupný spolehlivý přehled. |
| `pending` | Požadavek čeká ve frontě. |
| `preparing` | Připravuje se obsah či příloha zprávy. |
| `sending` | Probíhá pokus; další pokus se nevytváří. |
| `blocked` | Zpracování zadržuje platná podmínka fronty. |
| `accepted` | Poskytovatel zprávu převzal; příjemce ještě nepotvrdil doručení. |
| `delivery` | Zprávu převzal poštovní server příjemce. |
| `open` | Zaznamenané otevření může pocházet i z automatizace. |
| `click` | Zaznamenané kliknutí může pocházet i z automatizace. |
| `retry_wait` | Existující pokus čeká na řízené opakování. |
| `unknown` | Výsledek pokusu není potvrzen; nový resend je blokovaný. |
| `dead` | Požadavek dosáhl konečného selhání zpracování. |
| `bounce` | Poskytovatel zaznamenal nedoručení. |
| `complaint` | Byla zaznamenána stížnost na zprávu. |
| `suppressed` | Odeslání na normalizovanou adresu je blokované. |
| `reject` | Poskytovatel zprávu odmítl. |
| `rendering_failure` | Selhalo vykreslení obsahu poskytovatelem. |
| `delay` | Poskytovatel ohlásil zpoždění. |
| `cancelled` | Čekající požadavek byl zrušen. |
| `expired` | Požadavek už nelze zpracovat v původní platnosti. |
| `send` | Událost poskytovatele o odeslání. |
| `not_accepted` | Pokus nebyl potvrzen jako převzatý. |
| `done` | Následný krok je dokončený; nejde o důkaz přečtení. |
| `tracking_disabled` | Sledování otevření/kliknutí je vypnuté. |
| `not_observed` | Otevření/kliknutí nebylo pozorováno. |
| `post_action_failed` | Selhal navazující aplikační krok po odeslání. |
| `feedback_overdue` | Očekávaná zpětná vazba nepřišla včas. |

Lokální účty a objednávky jsou fiktivní. Předem připravené pohyby a události
slouží pro zobrazení scénářů. Nové místní změny se skutečně ukládají do DB.
Externí banka, karetní poskytovatel ani doručování na skutečné adresy nejsou
součástí této ukázky. Konkrétní kontroly a snímky uvádí
[záznam lokální kontroly](../plans/evidence/order-detail-local-review.md).


Po dalším upřesnění má oddělovač jedinou tenkou čáru v barvě tabulky,
ale ponechává širší neviditelnou plochu pro tažení. Číslo objednávky doplňuje
ikona otevření. Zrušení objednávky je viditelná akce s dosavadním potvrzením,
oprávněními a kanonickým příkazem. Odpovědi formuláře jsou otevřené od začátku;
chybějící názvy polí používají přeložený název typu místo textu null.

Výběr místa nebo vstupenky nemění přiblížení plánku. Vybraná vstupenka dostane
viditelné označení, rozbalí se a při výběru z mapy se zobrazí v seznamu. Plánek
začíná celkovým pohledem. Význam doručovacích stavů vysvětluje kompaktní sdílené
informační tlačítko; úplný seznam zůstává v této dokumentaci.


Aktuální detail používá stejné záložky TabBar jako ostatní části aplikace.
Předchozí/další objednávka a zavření jsou vpravo nahoře, zákaznický přehled
je přímo u čísla objednávky a zrušení objednávky je zarovnané vpravo.
Skrytá (interní poznámka) je přímo pod kontaktem. Ikona vstupenky zůstává
stejná; výběr rozlišuje podbarvení, oddělení a přístupný vybraný stav.
Posuvník má neviditelnou 48px plochu vycentrovanou na čáře po celé výšce;
panel lze zúžit na 360 px.

Nad kontaktem je zdrojový formulář s názvem a ID. Odpovědi se řadí podle
jeho aktuálních definic, včetně vlastních názvů a nastavených možností.
Produktová pole ukazují zakoupené produkty ze snapshotů podle identity
kategorie; nezobrazují fiktivní chybějící textovou odpověď. Cenové snapshoty
se při tom nepřepisují současným katalogem.

Odpovědi mají vlastní tužku u každého editovatelného pole. Pole přejde do
režimu úpravy. Výběrové pole nabízí nastavené možnosti formuláře. Při první
změně se pod záložkami zobrazí stálá lišta Uložit změny/Zahodit změny. Zůstává
viditelná při posouvání obsahu i přepínání záložek a platí pro všechny
rozepsané odpovědi a poznámku; v jednotlivých řádcích nejsou ukládací tlačítka.
Kontaktní e-mail se rovněž ukládá přes společnou akci a jeho dosavadního vlastníka,
bez požadavku na odeslání zprávy. Při souběžné změně se vstup zachová a novější
data se nepřepíší.
E-mail používá dosavadní opravu kontaktu, produkty produktový dialog.

Skrytá poznámka má jediný nadpis, hodnotu a tužku. Prázdný vstup neopakuje
nadpis; ukládání zajišťuje společná lišta změn. Neuložené odpovědi i poznámka
jsou součástí společné ochrany při zavření nebo změně objednávky.

Kolečko nad plánkem posouvá stránku. Přiblížení vyžaduje Ctrl/Cmd + kolečko
nebo gesto; ostatní použití sdíleného vieweru zachovávají dosavadní ovládání.
Panel má jedinou čáru bez dalšího úchopu a tooltipu. Celá její výška je
tažitelná v 48px oblasti vycentrované přesně na čáře s kurzorem resizeLeftRight.
Přidat platbu je před finančním souhrnem. Potvrzení zrušení používá jeden
společný dialog tabulky i detailu s výčtem objednávek a upozorněním, že po
zrušení už úpravy nejsou možné a platba se sama nevrátí. Návrat má popisek Zpět.

Escape zavírá detail stejnou cestou jako křížek. Otevřené dialogy mají
přednost; Escape v upravovaném údaji vyvolá ochranu neuložené změny. Aktivní
editor buňky tabulky si zachovává své běžné zpracování klávesy.


Společné uložení postupně používá dosavadní vlastníky jednotlivých údajů;
nejde o novou paralelní autoritu. Po každém potvrzeném zápisu načte aktuální
odpovědi pro další scope. Pokud pozdější krok selže, již potvrzené změny
zůstávají uložené a znovu se neposílají; lišta vysvětlí částečné dokončení a
ponechá neuložená pole rozepsaná. Čtecí plánek během této operace nespouští
vlastní obnovy, které by soupeřily o generaci detailu.

Upřesnění 2026-11-02: Zdrojový formulář se uvádí pouze při více formulářích
v aktuálním bundle objednávek. Skrytá poznámka používá kanonický překlad
z tabulky a je přímo editovatelná bez tužky; společná lišta nadále ukládá
a zahazuje všechny rozepsané hodnoty. Nadpis objednávky je tučný.

Upřesnění tažení 2026-11-02: neviditelná oblast je nyní 24 px
(12 px od středu čáry na každou stranu); nahrazuje předchozích 48 px.

Finální upřesnění uživatele: šířka oblasti tažení je 40 px (20 px na
každou stranu čáry), čímž nahrazuje předchozí zúžení na 24 px.

Doménová oprava 2026-11-02: odpovědi formuláře patří pouze objednávce.
Jméno účastníka a výběrová Strava byly nepodporované syntetické ticket
položky a jsou odstraněny včetně nově přidaného ukládání. Vstupenka
používá snapshot produktů a původní správu produktů, místa a poznámky.
Splitter nyní obsluhuje pointer události ve stejné oblasti jako kurzor
a reaguje již na první pixel pohybu bez prahu gesta.

Životní cyklus tažení 2026-11-02: samotný MouseRegion nestačí pro
zachycené tažení mimo původní oblast. Aktivní pointer vlastní také kurzor
v kořenovém Overlay; uvolnění, zrušení, ztráta fokusu a dispose odstraňují
obojí. Relativní delta po každé události umožňuje okamžitý návrat od mezí.

Webový splitter: Semantics slider musí mít SemanticsHitTestBehavior.transparent.
Jinak neviditelný HTML range input přepíše kurzor Fluttru na default.
Ověřujte computed cursor skutečného elementFromPoint, nejen styl body.
Přístupné akce a klávesnice zůstávají aktivní, pointer vlastní Flutter.

Odpovědi formuláře mají u upravitelné hodnoty jedinou tužku napravo
v řádku. Otevře pole inline, včetně e-mailu sdílejícího existující contact
draft; společné uložení a zahození zůstává jediným vlastníkem změn.
