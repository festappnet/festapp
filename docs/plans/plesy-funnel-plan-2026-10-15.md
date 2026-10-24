# Přehled plesů jako akviziční funnel vstupenky.online

Datum: 2026-10-15. Stav: rozpracovaný plán a připravené zadání pro budoucí realizaci; aplikace zatím neimplementována.
Ověření plánování: low-risk, jeden průzkum. Implementace veřejných dat a konverzního toku vyžaduje standardní cílené kontroly.

## Potvrzené priority a pracovní návrhy

Uživatel potvrdil: primární je výborná služba lidem hledajícím ples; vzhled má být prémiový, elegantní a přednostně tmavý. Lze porovnat více vizuálních směrů. AI znamená dohledatelnost v AI vyhledávačích, nikoli chatbota na stránce. Katalog zahrnuje i plesy mimo náš prodej; návštěvníka tehdy směruje na stránku pořadatele s informacemi o prodeji nebo rezervaci.

Pracovní značka po diskusi o doméně je **Plesuj**, zamýšlená vlastní doména **plesuj.cz**. Doména nebyla registrována; její dostupnost před nákupem ověřit. Pracovní návrhy, dosud nepotvrzené: první pilotní oblast, konkrétní paleta, rozsah bezplatného zápisu a provozní odpovědnost za aktualizace. Tyto návrhy nejsou překážkou rozpracování designu.

## Cíl a obchodní logika

Primárně stavíme výborný přehled pro lidi, kteří hledají, kam jít na ples. Musí jim pomoci objevit zajímavé akce, porovnat možnosti, najít správný termín a místo a dostat se ke vstupenkám. Důvodem k návštěvě i návratu je užitečnost a příjemné používání. Obchodním cílem je díky tomuto publiku získávat zákazníky pro vstupenky.online; obchodní vrstva je podpůrná a nesmí určovat hlavní obsah ani překážet hledání.

Navržená cesta:

Vyhledávání / sdílený odkaz → přehled podle místa a termínu → prohlížení a porovnání plesů v seznamu a na mapě → důvěryhodný detail → vstupenky nebo oficiální informace → sdílení a další návštěva.

Pořadatel má vlastní vedlejší cestu z nenápadného odkazu v navigaci či patičce na existující stránku pro pořadatele. Není dalším krokem běžného návštěvníka po detailu plesu. Konkrétní formulace a umístění obchodních výzev zatím nejsou rozhodnuté.

Souběžně funguje obchodní cesta: ověřený záznam z rešerše → konkrétní veřejný detail → individuální oslovení s odkazem → stejný tok pro pořadatele. Plán neopravňuje k rozesílání zpráv.

Aktualizované pracovní doporučení: samostatný průvodce **Plesuj** na **plesuj.cz**, transparentně propojený se vstupenky.online pro nákup a pořadatelskou cestu. Vlastní doména je volba značky a zapamatovatelnosti, nikoli zaručený SEO bonus. Nahrazuje původní preferenci sekce vstupenky.online/plesy. České plesy první, slovenské později. Název a rozsah nejsou publikovaným závazkem úplného pokrytí. Podklad a limity rozhodnutí shrnuje `docs/plans/plesuj-market-scan-2026-10-15.md`.

## Co má člověk na webu zažít

### Marketingové sdělení a SEO texty

Pracovní doporučení pro hlavní stránku:

- **Značka:** „Plesuj“. **Hlavní nadpis:** „Najděte svůj příští ples.“ Slovo plesy a pokrytí Česka přirozeně uvést v popisu a SEO titulku.
- **Podnadpis:** „Kam vyrazíte na ples? Vybírejte podle místa a termínu, prohlédněte si mapu a zjistěte, jak získat vstupenky.“
- **Doplňkový slogan pro kampaň nebo sdílení:** „Plesová sezona začíná tady.“
- **SEO title:** „Plesuj - přehled plesů v Česku, termíny a mapa“.
- **Meta description:** „Hledáte, kam na ples? Prohlédněte si přehled plesů v Česku podle místa a termínu. Potvrzené akce i jasně označený výhled na další ročníky.“

Slovo „přehled“ je pro veřejnost vhodnější než „databáze“: vyjadřuje, co zde člověk najde, a nesugeruje technický registr. Tyto texty jsou návrh copy, nikoli výsledek měření hledanosti klíčových slov. Základní tematické skupiny pro obsah jsou „plesy“, „kam na ples“, „plesy tento víkend“, „plesy + město/kraj“ a konkrétní názvy akcí. Používat je přirozeně podle skutečného obsahu stránky; nepřeplňovat nadpisy variantami stejného dotazu.

„Největší český přehled plesů“ je možná budoucí pozice značky, ne zatím ověřený fakt. Takový claim lze nasadit až po doložitelném porovnání stejné metriky, geografického rozsahu a období s relevantními přehledy. Počet pořadatelů v CRM, archivních záznamů nebo nepotvrzených odhadů se nesmí vydávat za počet aktuálních plesů. Stejně nepoužívat „všechny plesy“ nebo „kompletní přehled“, dokud tomu neodpovídá doložitelné pokrytí.

Pokud startujeme regionálním pilotem, hlavní titulek a metadata omezit na skutečně pokrytou oblast, například „Plesy v Moravskoslezském kraji. Najděte ten svůj.“ Jde o ilustraci formulace, nikoli zvolený pilotní kraj. Případné číslo na stránce odvozovat jen z publikovaných unikátních akcí a oddělovat potvrzené ročníky, očekávání a historii. Výhled zůstává označený i v SEO titulcích a sdílených náhledech.

### Hledání a prohlížení

- Úvod podle marketingového návrhu výše; při změně copy zachovat jasné slovo „plesy“. Pod ním ihned město nebo oblast, termín a výsledky. Žádná velká dekorace odsouvající hledání.
- Rychlé volby „Tento víkend“, „Příští víkend“, „Vybrat termín“, kraj a typ plesu. Vyhledávání názvu, obce a místa konání bez závislosti na diakritice. Okolí podle zadaného města; poloha zařízení pouze na vyžádání.
- Desktop: přehledné karty a vedle nich mapa. Mobil: přepnutí Seznam / Mapa, stále stejné filtry. Karta zvýrazňuje datum, název, obec, sál a doloženou cenu. Plakát slouží jako doplněk, důležité údaje jsou skutečný text.
- Detail: datum a čas, místo, mapa, program pokud ho známe, pořadatel, zdroj a aktuálnost informací. U vlastního prodeje hlavní akce vede přímo na existující formulář vstupenky.online. U ostatních plesů vede na stránku pořadatele s informacemi o vstupenkách; nevnucovat samostatný odkaz na konkurenční ticketing. Telefonní rezervace, prodej na místě či neznámý způsob prodeje jsou odlišné stavy, nikoli automaticky tlačítko „Koupit vstupenky“.
- Lidé mohou vybírat a otevírat detaily bez registrace. Nabídnout snadné sdílení konkrétní akce či výsledků. Při nulovém výsledku vysvětlit rozsah pokrytí a nabídnout širší oblast nebo jiný termín; nikdy nenahradit prázdný seznam obchodní reklamou.
- Odkaz pro pořadatele patří do vedlejší navigace nebo patičky. Opakované „Pořádáte tento ples?“ na kartách ani detailech není součástí návrhu. Možnost přidat nebo opravit akci lze navrhnout jako doplňkovou službu; její obchodní tok a cenu rozhodnout později.

Vizuální směr: tmavý prémiový kulturní průvodce, výrazná typografie, klidné pozadí, kvalitní fotografie či plakáty s povoleným užitím a velkorysé mezery. Konzistentní karty i bez obrázku. GoOut je inspirace pro objevování akcí a propojení s ticketingem; jeho vizuální provedení nebylo v tomto plánování detailně auditováno.

## Art direction: jak konkrétně dosáhnout prémiového vzhledu

### Povinný externí UI/UX skill

Na výslovný požadavek uživatele používat při návrhu a realizaci [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill), konkrétně jeho [SKILL.md](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/56ea9cf174ed86786187daa9de0e6247cb0747e4/.claude/skills/ui-ux-pro-max/SKILL.md). Zvolená revize: `56ea9cf174ed86786187daa9de0e6247cb0747e4`. Doplňuje stávající `ux-designer`; není jeho náhradou ani vlastníkem produktového zadání.

Skill byl přečten a nainstalován v kanonickém osobním repozitáři `/Users/miakh/source/development-tools/vendor/codex-skills/ui-ux-pro-max/`, včetně dat, vyhledávacích skriptů, licence a `UPSTREAM.md`. `scripts/install-skills.sh` vytvořil odkaz `/Users/miakh/.codex/skills/ui-ux-pro-max`. Před další session načíst tento `SKILL.md`. Skripty volat absolutní cestou; pluginovou proměnnou z upstream příkladů v tomto prostředí nepředpokládat.

Jak se skill skutečně zapojí:

1. Před koncepty provést `--design-system` pro zadání a cílené rešerše stylu a použitelnosti. Detekovaný frontend je vanilla JS/Vite a vlastní CSS; kvůli doporučení skillu nepřidávat Tailwind, React ani měnit stack.
2. Každý ze tří vizuálních konceptů doplnit konkrétními tokeny ploch, textu, akcentu, typografie, rozestupů a stavů. Při výběru vysvětlit vztah návrhu k plesům a skutečnému hledání. Převzatá doporučení podřídit tmavé eleganci, existující značce a návštěvnické prioritě.
3. Schválené volby uchovat v jednom katalogovém design dokumentu a používat pro všechny jeho stránky; nevytvářet automaticky druhou globální autoritu vedle tenantových tokenů. Přehled, mapa a detail dostanou pouze zdůvodněné odchylky.
4. Před předáním návrhu projít relevantní pravidla skillu pro kontrast, ovládání, responzivitu, feedback a navigaci. Při realizaci doložit použití na skutečných obrazovkách: mobil a desktop, focus, načítání, chyby a nulové výsledky. Kontroly provést v jedné cílené dávce podle pravidel repozitáře, nikoli po každé úpravě. Nativní app checklist přizpůsobit webu; nezavádět nové nativní požadavky.

První použití již proběhlo v plánování: vyzkoušen návrh design systému a cílené dotazy `filter search results`, `dark mode contrast` a `dark OLED`. Relevantní výsledky podpořily našeptávání, užitečný nulový výsledek, čitelný kontrast a tmavé plochy. Automatický systém ovšem navrhl i světlou paletu, dominantní hero a následně Apple Liquid Glass; tyto části neodpovídají briefu a nebyly přijaty. Skill je podklad pro návrhářský úsudek, nikoli automatický generátor schváleného vzhledu. Do aplikace se zatím žádný návrh nepropsal.

### Porovnávané směry

Prémiovost musí vycházet z kompozice, typografie, fotografie a detailu ovládání. Pracovní směry pro porovnání na stejném obsahu:

| Směr | Vzhled | Silná stránka a riziko |
|---|---|---|
| A. Večerní editorial - doporučený výchozí návrh | Antracit, teplý světlý text, střídmý champagne akcent; velký nadpis, promyšlená fotografie, precizní mřížka | Slavnostní atmosféra a čitelné hledání; uhlídat, aby akcent a písmo nekolidovaly se značkou |
| B. Současná kulturní scéna | Temně modrý nebo inkoustový podklad, výraznější práce s existující značkou, odvážnější typografie a obrazové výřezy | Modernější a živější; nepřehlušit datum a místo dekorací |
| C. Slavnostní minimalismus | Tmavé plochy, větší podíl typografie, jemné linky a méně obrazů | Drží kvalitu i při slabých plakátech; musí zůstat lákavý a nevyznít jako strohý seznam |

Konkrétní odstíny ani nový font nejsou schválená změna globálního brandu. Nejprve využít existující kvalitní písma a tenantové tokeny; případný odlišný katalogový styl omezit na jeho obsah. Existující společné komponenty a uživatelská nastavení tématu zůstávají respektované. Prezentace samostatné značky Plesuj se omezuje na průvodce; nepřejmenovává ticketing vstupenky.online. Primárním návrhem je tmavá varianta, světlá varianta společného tématu musí zůstat použitelná.

Pravidla vizuálního zpracování:

- Úvod kombinuje krátký výrazný titulek, hledání a ochutnávku skutečných akcí. Na běžném mobilu nesmí první obrazovku obsadit samotný slogan nebo fotografie.
- Fotografie a plakát mají různé role. Fotografii lze řízeně oříznout; plakát nesmí ořezem přijít o obsah. Důležité údaje vždy zopakovat čitelným textem. Záložní karta bez fotografie má stejnou péči a informační hodnotu.
- Karta má stabilní hierarchii: datum, název, obec a sál, následně cena nebo způsob prodeje. Omezit počet štítků a držet zarovnání mezi kartami. Celá karta odkazuje na detail bez vnořených konfliktních odkazů.
- Mapa musí vizuálně sedět k tmavému webu, ale české názvy a silnice zůstávají čitelné. Ověřit skutečný dostupný podklad; neobracet jeho barvy CSS filtrem. Když je vhodnější světlý podklad, zasadit jej jako záměrně světlejší plochu.
- Pohyb je krátký a účelný: odezva filtru, jemné zvýraznění vybrané karty/bodu. Respektovat omezení animací. Bez automatického carouselu, videa na pozadí a neustále se pohybujících dekorací.
- Ovládání musí fungovat klávesnicí, mít viditelný focus a čitelný kontrast. Mobilní cíle navrhovat alespoň kolem 44 px. Cena a dostupnost se nesdělují jen barvou.

Výstup vizuální fáze: tři stručné vizuální koncepty stejného úvodu a karet na desktopu i mobilu; poté jeden vybraný směr rozpracovaný do hledání, mapy, detailu a chybových stavů. Žádný směr se nevybírá pouze podle velkého hero obrázku. Tento plán sám koncepty ještě nevytváří.

## Klíčové návštěvnické situace

| Situace | Požadované chování |
|---|---|
| „Chceme někam příští víkend u Ostravy“ | Vybrat lokalitu a příští víkend; výsledky ihned ukazují datum, obec a případnou vzdálenost. Rozsah okolí je viditelný a změnitelný |
| „Jen se chci inspirovat“ | Vidět nadcházející plesy i bez zadání dotazu; možnost přejít do regionu nebo procházet mapu. Výchozí řazení podle blízkého data, po zadání okolí zohlednit vzdálenost |
| „Hledám konkrétní ples“ | Hledání podle názvu, obce i sálu; našeptávání rozlišuje místa od akcí. Detail má vlastní sdílitelnou adresu |
| „Vrátím se z detailu“ | Zachovat filtry, pozici seznamu i výřez mapy. Tlačítko Zpět nesmí začínat hledání od nuly |
| „Nic tady není“ | Uvést, že nemáme ověřený záznam pro zvolený výběr; neprohlašovat, že se žádný ples nekoná. Nabídnout změnu termínu či oblasti až se souhlasem návštěvníka |
| „Jak získám vstupenky?“ | Rozlišit vlastní online prodej, informace u pořadatele, doloženou telefonní rezervaci a prodej na místě. Nedoloženou dostupnost nikdy neoznačit jako volná místa |
| „Ples je vyprodaný nebo zrušený“ | Jasný stav, funkční oficiální informace a alternativy ve stejném okolí nebo termínu; nepředstírat možnost nákupu |

Bez přihlášení lze hledat, měnit filtry, prohlížet mapu, otevírat detail a sdílet. Uložení oblíbených může přijít později; první verze kvůli němu nezískává nový účetní nebo notifikační tok.

## SEO a dohledatelnost v AI vyhledávačích

Potvrzený rozsah AI: vyhledávače mají naše aktuální údaje najít, pochopit a případně odkázat na příslušnou stránku. Chatbot, placený modelový provoz ani AI doporučování na webu do první verze nepatří.

### Obsahové vstupy a adresy

| Typ stránky | Záměr hledání | Obsah a pravidlo publikace |
|---|---|---|
| `/` | Přehled plesů, kam na ples | Hledání, skutečné nadcházející akce, vstupy do pokrytých oblastí, pravdivě uvedený rozsah |
| `/mista/<slug>` | Plesy v Brně, plesy na jižní Moravě | Jasně definovaná obec nebo kraj, aktuální výsledky a užitečný místní kontext. Rozlišovat stejnojmenné obce; bez automatické výroby všech kombinací |
| `/tento-vikend` a `/pristi-vikend` | Plesy tento nebo příští víkend | Stabilní adresa, na stránce i v titulku konkrétní datum rozsahu. Přepočet podle místního času; aktualizace HTML i cache při změně víkendu |
| `/akce/<slug>` | Název plesu + obec + ročník | Jedna stránka pro konkrétní doložený ročník, datum, místo, prodej a zdroje; slug obsahuje ročník a při případné změně má řízený redirect |

Místní a víkendové vstupy zařadit do první funkční verze pouze v rozsahu podloženém pilotem. Desítky filtrů nejsou desítky obsahových landing pages. Kombinace jako město + typ + víkend mohou fungovat interaktivně bez nového indexovaného dokumentu.

### Technická pravidla

- Ve výchozím HTML musí být nadpis, skutečné karty s odkazy, datum a lokalita; u detailu podstatné údaje a zdroj. Robot ani člověk nesmí pro získání základních informací nejprve obsluhovat mapu.
- Každá indexovaná obsahová stránka má vlastní title, popis, jeden hlavní H1, canonical, sdílecí metadata a odkazy z odpovídajících přehledů. Sitemap uvádí pouze kanonické publikované obsahové URL. `lastmod` odpovídá skutečné změně obsahu.
- Politika filtrů se určí explicitně: běžné neindexované kombinace mají `noindex` a zůstávají dostupné pro procházení této direktivy. Canonical na obsahový ekvivalent se používá pouze u skutečně duplicitních variant; neodkazovat bez rozmyslu všechny filtry na hlavní přehled. Nevyužívat `robots.txt` současně tak, že zabrání přečtení požadovaného `noindex`.
- Jednotlivý detail dostane JSON-LD `Event` s doloženým názvem, termínem, místem a stavem. Cena, dostupnost, konec akce a prodejní nabídka se přidávají pouze pokud je skutečně známe a jsou shodné s viditelným obsahem. Seznam plesů se nevydává za jednu událost. Zobrazení rozšířených výsledků závisí i na aktuální podpoře země/jazyka; není slíbeným výsledkem.
- Pozor na existující `SeoService.updateMetaTags`: nyní obsluhuje formuláře a odstraňuje query i fragment. Nový katalog nesmí tuto logiku slepě převzít a ztratit význam svých samostatných obsahových stránek. Současná sitemap v `handleSitemap` vychází z vlastních Occasions; musí zahrnout i publikované externí plesy přes jejich veřejný model.
- Neexistující detail vrací skutečné 404. Zrušený nebo proběhlý doložený ročník může zůstat dostupný s jasným stavem; každý nový ročník má novou identitu. Neznámý budoucí termín se nedopisuje kvůli SEO. Chování prázdných regionálních přehledů rozhodnout podle jejich trvalé užitečnosti, nevytvářet plošně indexované prázdné stránky.

### Co konkrétně pomůže strojovému porozumění

Praktický návrh: každý detail začne krátkou faktickou odpovědí „[Název] se koná [datum] v [sál, obec]. [Doložený způsob získání vstupenek].“ Pak následují přehledné pojmenované údaje, zdroj a datum kontroly. Text nevytváří další fakta; neznámá informace zůstává neznámá. Stejné identity, datum a názvy míst se používají v HTML, JSON-LD, mapě i sdíleném náhledu. Údaje nezamykat do plakátu či canvasu.

Pro Google AI funkce platí základní SEO: přístupnost robotům, indexovatelný obsah, vnitřní odkazy a text odpovídající strukturovaným datům. Zvláštní „AI soubor“ ani nové schema nejsou podmínkou. Účast a citace nelze garantovat. Viz [Google - AI features and your website](https://developers.google.com/search/docs/appearance/ai-features). JSON-LD navrhnout podle [oficiální dokumentace Event](https://developers.google.com/search/docs/appearance/structured-data/event).

Při implementaci samostatně ověřit aktuální pravidla přístupu vyhledávacích robotů relevantních AI služeb a nastavení CDN. Nepředpokládat, že povolení vyhledávání vyžaduje plošné povolení tréninkových robotů. Způsobilost k indexaci není důkaz skutečné citace.

### Ověření a měření

Před spuštěním zkontrolovat jednu stránku od každého typu: stav HTTP, HTML bez JS, canonical, robots, sitemap a shodu JSON-LD s obsahem. Ověřit aktuální metodiku pro Event a validovat reprezentativní detail. Pomocí Search Console po autorizovaném spuštění sledovat indexaci a dotazy podle měst, termínů a názvů akcí.

Návštěvy z AI zdrojů sledovat tam, kde je zdroj skutečně rozpoznatelný. Google uvádí návštěvy z AI funkcí ve společném webovém reportu Search Console, takže plán neslibuje jejich úplné samostatné změření. Kontrolní dotazy zaznamenávat s datem, lokalitou a výsledkem; několik ručních citací není stabilní metrika pořadí.

## Jak užitečný přehled podpoří získávání zákazníků

1. **Získat hledající publikum.** Přesné stránky akcí a postupně kvalitní přehledy měst a krajů pro dotazy typu „plesy Brno“ a „plesy tento víkend“. Indexovat jen stránky s užitečným obsahem, ne prázdné kombinace filtrů. Sdílené URL zachovávají filtr.
2. **Nabídnout pořadateli samostatnou cestu.** Přes vedlejší odkaz pro pořadatele nabídnout opravu termínu, doplnění programu nebo zaslání nového plesu. Předat identitu vybrané akce do formuláře, nechat zadat jen chybějící údaje a kontakt. Veřejný obsah vzniká až po kontrole; formulář sám nezakládá oprávnění k cizí akci.
3. **Nabídnout konkrétní navazující hodnotu.** Po podání údajů nabídnout existující cestu k založení prodeje a alternativně konzultaci. Vysvětlit přínosy relevantní pro ples: místenky, online prodej a odbavení, podle reálných schopností produktu. Neslibovat garantovaný dosah ani neověřené výsledky.
4. **Navázat obchodně.** V CRM uchovat zdroj leadu, příslušný ples a stav dalšího kroku. Obchodník může použít hotový detail při individuálním oslovení. Bez automatického oslovování a bez přepisování jeho ručních poznámek.
5. **Ověřit užitek i obchodní výsledek.** Produktově sledujeme úspěšnost hledání, četnost nulových výsledků, otevření relevantního detailu, přechod na vstupenky a návraty návštěvníků. V prototypu ověříme, zda člověk skutečně našel vhodný ples; samotné množství kliků může znamenat i zmatení. Obchodně samostatně sledujeme kvalifikované poptávky a získané pořadatele se spuštěným prodejem. Obchodní výsledek následně potvrzují placené objednávky. Návštěvnost ani klik na tlačítko není získaný zákazník.

Do analytiky předávat pouze nezbytné identifikátory a zdroj, nikoli obsah kontaktů a poznámek. U kvalifikované poptávky potřebujeme identifikovatelnou skutečnou akci a použitelný kontakt na jejího pořadatele. Propojení se spuštěným prodejem má vycházet z uloženého vztahu k akci, ne pouze z browserového kliknutí. První pilot stanoví výchozí konverzi; číselný cíl nezaměňovat za odhad bez dat.

## Data a jejich aktuálnost

Ověřený výchozí stav:

- Existující prospecting workflow má Google Sheet s pořadateli a lokální SQLite index `~/.local/share/festapp/plesy-research/prospects.sqlite3`. Dne 2026-10-15 byl index přečten v režimu read-only: 4 012 importovaných řádků (4 007 Kontakty, 5 K doplnění) ze snapshotů z 2026-10-08. Navíc obsahuje 41 574 archivních pozorování, která nejsou dalšími unikátními plesy. Aktuální webové zdroje ani živé Sheets při tomto čtení ověřeny nebyly. Podrobnosti: `docs/plans/plesy-funnel-sqlite-audit-2026-10-15.json`.
- Evidence workflow rozlišuje pořadatele, doložený ročník, zdroje a obchodní poznámky. Sheet je autorita pro obchodní práci, lokální index je pomocný. Odkaz: [existující workbook](https://docs.google.com/spreadsheets/d/1F_8UBOV8PYF0PBYBiPfdJeFyx00aAe6qIo7QE6zz8C4/edit).
- Současný katalog vlastních akcí používá `web_client/src/components/occasion/catalog.js`; přehled nalezených externích plesů nemá automaticky stejný datový a oprávňovací význam jako prodávaná Occasion.

Zásadní pravidlo: pořadatel, opakující se ples a konkrétní ročník jsou odlišné entity. Datum z roku 2026 neznamená potvrzený termín v roce 2027. Kontaktovatelný pořadatel také neznamená publikovatelný budoucí ples.

Navržený veřejný model vlastní kanonický backend Festapp: pořadatel → ples → ročník; místo konání s adresou a ověřenými souřadnicemi; zdroje a čas ověření; jistota konání a přesnost termínu; stav publikace; případně vazba na existující Occasion a skutečný prodejní odkaz. Publikace jako potvrzená akce s přesným termínem vyžaduje doložené datum, název, obec/místo a ověřený zdroj. Očekávané ročníky lze publikovat podle samostatných pravidel níže bez vymyšleného data. Neznámý čas nebo cena zůstávají neznámé. Bez přesné polohy neumisťovat falešně přesný bod na sál.

Import z rešerše je kontrolovaný a opakovatelný podle stabilních identit a zdroje. Návrhy aktualizací mají kontrolu před publikací. Poznámky obchodníka, stav oslovení a interní kontakty se do veřejného API vůbec neexportují. Změna v CRM sama nepřepíše potvrzený veřejný ročník. Jediný veřejný model obsluhuje seznam, mapu i SEO stránky.

Termíny filtrovat v místním pásmu: CZ `Europe/Prague`, později SK `Europe/Bratislava`. „Víkend“ navrhujeme pátek až neděli včetně, i po sobotní půlnoci stále tentýž víkend. Minulé ročníky zůstanou označeným archivem; neprojdou do nadcházejících výsledků. Zrušené a přesunuté akce dostanou jednoznačný stav a opravené odkazy.

## Očekávané ročníky a poctivé zacházení s nejistotou

Tato kapitola rozšiřuje původní návrh: katalog smí pomáhat s výhledem na sezonu i před zveřejněním konkrétních termínů. Očekávání není potvrzená akce a nový ročník nesmí zdědit jistotu, cenu, místo ani prodej z minulého ročníku.

### Co skutečně ukázala SQLite

| Zjištění v lokálním snapshotu | Důsledek pro realizaci |
|---|---|
| 3 987 řádků má neprázdné pole ročníku/data; 1 354 zmiňuje 2027, 2 422 zmiňuje 2026, 91 zmiňuje oba roky | Jde o textové výskyty, nikoli počty potvrzených ročníků. Jeden řádek může míchat historii a výhled |
| 57 polí ročníku obsahuje hledaná slova nejistoty | Tento detektor zachycuje jen část problémů. Absence slova „nepotvrzeno“ není potvrzení |
| 3 997 řádků má zdroj akce, jen 3 618 z nich obsahuje textovou HTTP URL | Některé zdroje jsou jen popisky odkazů. Pokusit se dohledat cíle v původních archivovaných podkladech/CellData, jinak znovu vyhledat; popisek není důkaz obsahu |
| Pole ceny je vyplněno u 3 465 řádků, zdroj ceny u 1 624; ne všechny hodnoty jsou číslo nebo aktuální nabídka | Neimportovat automaticky cenu jako cenu nového ročníku |
| Jeden pořadatel může v jediném poli uvádět několik plesů i jiný typ akce | Nejprve rozdělit identity akcí. Kalendář kapely může mít více plesů stejné školy; různé datum samo neprokazuje další ročník |
| Stávajících 18 sloupců nemá samostatnou jistotu, přesnost termínu, ověřené souřadnice ani vazbu faktu na konkrétní ročník | Veřejný model vyžaduje strukturované obohacení. SQLite nelze pouze vystavit jako hotový katalog |

Ilustrace z uložených dat, nikoli nová živá ověření:

- Florbal Hradec Králové: 22. 1. 2027 uvádí kalendář kapely a záznam výslovně říká „nepotvrzeno klubem“. Přesný den je známé tvrzení třetí strany, ne potvrzený termín pořadatele.
- Myslivecký spolek Pilníkov: „leden 2027 - přesný den zatím neoznámen“, zdroj uložen jen jako „Otevřít zpravodaj“. Nejprve obnovit a ověřit zdroj, pak rozhodnout, zda jde o oznámené období, nebo pouhý odhad.
- Zaklínačský ples / Con Morhen: „Leden 2027 (přesný termín čeká na zveřejnění)“. Pokud živá oficiální stránka tento měsíc potvrzuje, jde o oznámený ročník bez dne; nelze jej zaměnit za termín odhadnutý z historie.

### Dvě nezávislé osy místo procentuálního skóre

1. **Jistota konání nového ročníku:** `announced` - doložené oznámení odpovědného pořadatele nebo jeho autorizovaného zdroje; `reported` - tvrzení třetí strany bez takového potvrzení; `inferred` - odhad z ověřené historie; `unknown` - bez dostatečného podkladu. Zrušení, přesunutí a rozporné zdroje řešit jako další stav konání/ověřování, ne jako úroveň přesnosti data.
2. **Přesnost termínu:** `day`, `month`, `range`, `season`, `unknown`. Platí i u oznámeného ročníku. „Pořadatel oznámil leden“ je jistější informace o konání než „podle loňska asi leden“, přesto oba záznamy nemají den.

Zvlášť uložit platnost a původ místa konání, ceny, programu a prodejního odkazu; jeden potvrzený údaj nesmí posvětit celý záznam. Zdroj každého důležitého tvrzení obsahuje URL, roli zdroje, datum kontroly a relevantní doložený text. Archivní pozorování má datum zachycení, které není automaticky datem ověření. Ruční kontrola zaznamená autora a výsledek. Nezavádět nepodložená procenta typu „85% jistota“.

### Doplnění modelu a pravidla odhadu

Navržená pole na výhledu/ročníku: stabilní identita plesu a sezony, `occurrence_certainty`, `date_precision`, volitelné skutečné datum/čas, očekávané období s rokem, `expectation_basis`, reference na historické ročníky, `source_assertions`, `verified_at`, `review_after` a stav publikace. Konkrétní SQL názvy a typy dokončit ve fázi datového kontraktu. Časové intervaly očekávání nesmí být vydávány za skutečné datum akce ani za její délku.

- Odhad se váže ke konkrétnímu plesu a zamýšlené sezoně, ne pouze k pořadateli. Předpoklad, že se jednorázový ples bude každoročně opakovat, musí projít kontrolou.
- Při více srovnatelných doložených ročnících lze navrhnout obvyklý měsíc nebo rozmezí. Zachovat posuny související s pohyblivými svátky; nepřenášet mechanicky den a měsíc do dalšího roku.
- Při jediném známém ročníku lze po kontrole ukázat pouze opatrný výhled „Minule v lednu; další ročník zatím nepotvrzen“. Konkrétní očekávaný leden daného roku je redakčně posouzený odhad s tímto vysvětlením, nikoli automatický fakt.
- Pokud je evidence slabá nebo protichůdná, zůstat u „Další ročník zatím neoznámen“ na profilu plesu. Nevyplňovat měsíc jen kvůli hustotě katalogu. Zrušenou nebo zaniklou akci automaticky znovu neočekávat.
- Před uveřejněním zkontrolovat nový ročník na oficiálním webu/kalendáři pořadatele, případně obce, sálu či školy v odpovídající roli. Kapela a jiný portál jsou užitečný podnět k ověření. Každé tvrzení potřebuje správnou identitu akce a sezony.

### Jak nejistotu uvidí návštěvník

| Podklad | Hlavní text karty a detailu |
|---|---|
| Oznámený přesný den | „23. ledna 2027“; zdroj a poslední kontrola na detailu |
| Pořadatel oznámil pouze měsíc | „Leden 2027 - přesný termín ještě není zveřejněný“ |
| Měsíc odhadujeme z historie | „Očekáváme v lednu 2027 - ročník zatím nepotvrzen“ + „Odhad podle minulých ročníků“ |
| Přesný den uvádí jen třetí strana | „Termín čeká na potvrzení pořadatelem“; konkrétní uváděné datum a jeho zdroj až s jasným vysvětlením na detailu |
| Nemáme podklad pro období | „Další ročník zatím neoznámen“ a odděleně poslední doložený ročník |

Nejistota je v hlavní datové části karty i v úvodu detailu, neskrývá se v tooltipu. Stav musí být čitelný textem a vizuálně konzistentní s prémiovým designem. Tlačítko u nepotvrzeného ročníku vede na oficiální informace, nikoli na nákup minulého ročníku.

### Filtry, mapa, stránky a životní cyklus

- Výběr konkrétního dne nebo víkendu standardně vrací pouze oznámené a ověřené přesné termíny. Měsíční odhad se nesmí objevit mezi výsledky každého víkendu v daném měsíci. U výsledků vysvětlit tento rozsah.
- Měsíční, sezonní a regionální prohlížení může nabídnout oddělenou sekci „Očekávané plesy - termíny zatím nejsou potvrzené“. V ní navíc rozlišit oznámený měsíc a odhad. Počty potvrzených a očekávaných výsledků uvádět samostatně. Při víkendovém hledání lze nabídnout přechod na tuto širší sekci, nikdy ji vydávat za shodný přesný filtr.
- Mapa zobrazuje stejnou vybranou kategorii výsledků jako seznam. U očekávaných akcí neprezentovat loňský sál jako letošní potvrzené místo. Je-li ověřena jen obec, použít jasně označenou obecní polohu a uvést „Místo pro nový ročník není potvrzené“; jinak bod nezobrazovat.
- Přidat stabilní profil opakujícího se plesu `/ples/<slug>` pro historii a výhled. Odhad může být publikován jako výhled sezony na tomto profilu bez vytvoření falešné naplánované akce. Konkrétní ročník má stabilní interní identitu; po potvrzení se stejný výhled povýší, nevznikne druhý importovaný ročník.
- SEO metadata a sdílený náhled musí zopakovat nejistotu. Spekulativní termín se nikdy neexportuje jako `Event.startDate`, dostupné vstupenky ani kalendářová pozvánka. Profil lze popsat běžným `WebPage`; `Event` se přidá pro skutečně doložený konkrétní ročník s přesným dnem. Nevymýšlet první den měsíce jako technickou náhradu. Užitečný zdrojově podložený profil může být indexovaný, prázdný automatický výhled ne.
- Jakmile zdroj oznámí den, zkontrolovat identitu, změnit jistotu a přesnost, aktualizovat viditelný text, mapu, filtry, canonical podle skutečné stránky, sitemap, náhled a cache. Staré historické údaje se nepřepisují novými. Znovu ověřit také místo, cenu a prodej.
- Po uplynutí očekávaného období bez potvrzení změnit text na „Aktuální ročník se nepodařilo potvrdit“ a vyřadit z nadcházejícího očekávání. Neposouvat automaticky odhad do dalšího měsíce nebo roku. Konflikt zdrojů poslat ke kontrole, nezvolit tiše výhodnější datum.

### Co doplnit před zveřejněním, v pořadí hodnoty

1. **Identita:** čitelný název a diakritika z původních hodnot, konkrétní ples versus pořadatel, oddělení více akcí v jednom řádku a vyloučení neplesových akcí. `records.name` a `locality` jsou normalizované pomocné hodnoty, ne hotové veřejné názvy.
2. **Konání a termín:** rozdělit historická data a výhled, obnovit URL zdrojů, dohledat oznámení nového ročníku, uložit jistotu, přesnost a podklad pro případný odhad.
3. **Lokalita:** kanonická obec/kraj, země, sál, adresa a ověřené souřadnice; potvrzené versus historické místo pro nový ročník. Text v současném sloupci Místo není automaticky platná adresa.
4. **Vstupenky:** oficiální stránka s postupem nákupu, způsob prodeje a doložená aktuální cena, pokud je zveřejněná. Starou cenu ukázat jedině jako cenu minulého ročníku, mimo současnou nabídku. CRM telefon se nezveřejní bez ověření, že je určený k veřejným rezervacím.
5. **Obsah pro výběr:** typ plesu, veřejný/soukromý charakter, program a kapela, začátek, fotografie/plakát a právo k užití. Dress code a přístupnost doplnit, pokud jsou doložené; neodvozovat je z typu akce.

Pilot má obsahovat všechny důležité kategorie jistoty, ne jen nejsnazší přesná data. Kontrola musí prokázat, že stejný import je opakovatelný, že cena minulého ročníku nepřejde do nového a že oznámený měsíc, historický odhad a datum třetí strany zůstanou odlišitelné v UI i datech.

## Mapa a rychlost

Preferovaný kandidát je základní podklad Mapy.com, načítaný až při potřebě. Konkrétní knihovnu vybrat při prototypu z podporovaných integrací podle jednoduchosti a chování shluků bodů. Mapy.com poskytují rastrové dlaždice a vyžadují atribuci; provoz má spotřební ceník. Před zapojením ověřit aktuální podmínky, doménové omezení klíče a rozpočet, bez automatické aktivace placené spotřeby.

Mapa a seznam musí sdílet filtry, výsledky a výběr. Shlukovat body, klikem ukázat stručný náhled a detail. Posun mapy mění výsledky až po „Hledat v této oblasti“, aby uživatel neztrácel orientaci. Výpadek mapy neblokuje seznam. Geokódovat a ověřit místo při přípravě dat, ne opakovaně při každé návštěvě; ukládání výsledků musí odpovídat podmínkám služby.

Stránky mají čitelné HTML už před spuštěním JS; obrázky mají rozměry a náhledy, mapa je samostatně načítaný modul. Požadovaný výsledek je svižné hledání i na mobilních datech. Při realizaci ověřit LCP, CLS a interakce na reprezentativním objemu dat, nikoli jen na prázdném seznamu.

Zdroje ověřené při plánování: [GoOut](https://goout.net/cs/), [Mapy.com - dlaždice](https://developer.mapy.com/rest-api-mapy-cz/function/map-tiles/), [atribuce](https://developer.mapy.com/rest-api-mapy-cz/atribution/), [ceník](https://developer.mapy.com/pricing/).

## Zapojení do současného webu

- Rozšířit existující lehký webový klient, veřejný přehled nenačítá Flutter jen kvůli hledání. Kandidátní nové komponenty pod `web_client/src/components/balls/`, vstupní větev v `web_client/src/main.js` a URL v existujícím směrování. Konkrétní routy na doméně Plesuj: `/`, `/akce/<slug>`, `/ples/<slug>` pro profil a nejistý výhled; místní a víkendové stránky podle SEO kapitoly.
- Respektovat bootstrap `web_client/src/startup/initialize_core_services.js`, sdílenou hlavičku a značku. Nevytvářet druhou implementaci přihlášení.
- Navázat na plán `docs/plans/vstupenky-organizers-ui-plan-2026-10-15.md` a existující `web_client/src/startup/organizer_intent.js`. V implementaci ověřit aktuální stav `/pro-poradatele` a bezpečné předání kontextu akce; plán jiné session není důkaz dokončené funkce.
- Veřejné HTML, canonical a sitemap zapojit do současného buildu: `automation/cloudflare_build.sh`, existující renderovací vzor `automation/release/render_organizer_page.mjs` a `web_client/src/services/seo_service.js`. Projít také mapování veřejných dokumentů v `automation/lib/pwa_shell_manifest.mjs` a generátoru service workeru. Žádný samostatný Sites hosting ani souběžná databáze veřejných plesů.
- Nové SQL patří do kanonických repository SQL a řízené migrace. Veřejné čtení obsahuje jen publikovaná pole. Vkládání návrhů je omezené proti spamu; úpravy publikovaných dat vyžadují ověřené oprávnění a kontrolu. Notifikace používají existující `public.email_messages`, pokud budou vůbec v první verzi potřeba.

## Vlastní doména: realizační hranice

Před implementací potvrdit cílový origin; příklady nových veřejných rout v tomto plánu jsou již relativní k zamýšlené doméně Plesuj. Veřejný katalog má jednu kanonickou adresu a vlastní čitelnou značku, existující prodejní formuláře a přihlášení zůstávají na vstupenky.online. Odkaz pro pořadatele vede na skutečnou stránku `https://vstupenky.online/pro-poradatele`, nikoli automaticky na stejnou cestu nového hostu. Nevytvářet druhé účty ani nové zákaznické přihlášení jen kvůli katalogu.

Současný build/router některá chování podmiňuje hostem a tenantovou konfigurací, například `ORGANIZERS_ENABLED` v `automation/cloudflare_build.sh`. Před použitím nové domény navrhnout explicitní oddělení originu veřejného průvodce od originu ticketingu, zkontrolovat host routing, canonical, sitemap, CSP/CORS, PWA a odkazy. Nepřepsat globální `WEB_LINK` existujícího ticketingu na novou doménu. Nový katalog nepředstavuje automaticky novou Organization/tenant ani souhlas k vytváření další prod větve. Sdílený backend a kód nadále vlastní main.

Doména, DNS a hosting zatím nejsou nastavené. Samostatný deploy průvodce a případná související změna vybraného ticketing tenantu jsou provozní kroky pouze v rozsahu následného zadání. Samotná doména se tímto plánem nekupuje. Pokud se finálně zvolí jiný origin, upravit tuto část, URL kontrakt a prompt společně; nepublikovat paralelní indexované kopie na více doménách.

## Doporučený postup

### 1. Datový pilot pro užitečné hledání

Přečíst čerstvou omezenou část existující rešerše, spočítat skutečně doložené budoucí ročníky a ověřit jejich zdroje. Navrhujeme začít jednou oblastí s nejlepšími daty a desítkami kvalitních záznamů, nikoli čekat na celou republiku. Výsledkem je schválený seznam publikovatelných polí a první sada akcí, na které si člověk opravdu může vybrat podle místa a víkendu. Geograficky úzký nebo řídký vzorek nesmí vést k dojmu úplného celostátního přehledu. Pokud máme jen historické ročníky, doplnit aktuální informace nebo po kontrole zveřejnit poctivě označený výhled podle kapitoly o nejistotě. Nelze jím nahradit potvrzenou nabídku konkrétního víkendu.

Kontrola: zkušební import bez zápisu ukáže počty přijatých, odmítnutých a duplicitních ročníků, důvody a původ; rozliší oznámené přesné dny, oznámené měsíce, tvrzení třetích stran, historické odhady a neznámé termíny. CRM zůstane beze změn. Rozsah a čerstvost pilotu musí být viditelné.

### 2. Vizuální prototyp

Nejprve připravit tři stručné koncepty stejného obsahu podle art direction výše, s preferencí tmavé elegance. Poté rozpracovat vybraný směr pro desktop a mobil především pro návštěvníka: úvod a hledání, výsledky s mapou, detail, sdílení a nulový výsledek. Vedlejší vstup pro pořadatele nesmí soutěžit s výběrem plesu. Použít reprezentativní podklady z pilotu, včetně chybějícího plakátu, ceny nebo polohy, potvrzeného dne, oznámeného měsíce a odhadovaného nepotvrzeného ročníku. Lokální prototyp je samostatné statické HTML bez serveru; externí mapa vyžadující klíč může být v návrhu jasně označenou vizuální ukázkou.

Kontrola: člověk bez vysvětlování najde ples příští víkend v okolí, porovná možnosti a zjistí kde, kdy a jak získat vstupenky. Rozhraní je příjemné i pro nezávazné prohlížení. Odkaz pro pořadatele je dohledatelný, ale neruší. Tato fáze slouží k rozhodnutí o vzhledu, ne jako hotový funkční portál.

### 3. První funkční verze

Kanonický veřejný model a kontrolovaný import, přehled, filtry, mapa, detail, SEO HTML a obsahové vstupy podle samostatné SEO kapitoly, podání návrhu a návaznost na existující prodejní/organizační cestu. Vlastní prodej vede přímo na náš formulář; ostatní akce na stránku pořadatele s informacemi. Navázat poptávku na CRM beze změny ručních obchodních údajů. Doplnit minimální měření užitečnosti i obchodního výsledku a technické omezení mapových nákladů.

Kontrola: cílené JS a SQL testy publikace a oprávnění, přes půlnoc a konec roku ověřené víkendy, opakovaný import bez duplicit, shoda seznamu s mapou, přímé otevření detailu, žádná interní data v anonymní odpovědi. Pro víkendové stránky ověřit i aktualizaci serverového HTML a cache při změně období. Izolované headless ověření mobilu a desktopu včetně návratu z detailu, externích informací o prodeji, konverzní cesty a výpadku mapy. Ověřit SEO matici jednotlivých typů stránek podle předchozí kapitoly. Přesné testové soubory doplnit s realizací podle stávajících testovacích seamů; nespouštět celou Flutter sadu pro samostatné veřejné UI.

Hotovo: anonymní návštěvník může pohodlně procházet ověřené plesy, najde vhodnou akci podle místa a termínu, otevře přehledný detail a pokračuje na skutečné vstupenky nebo oficiální informace. Mapa, filtry, sdílení a prázdné výsledky fungují i na mobilu. Vedlejší cesta pořadatele umožní skutečný návrh/poptávku a návaznost na spuštění prodeje; propojení zdroje s obchodním výsledkem je ověřitelné. Klikací maketa tento stav nesplňuje.

### 4. Omezené spuštění a vyhodnocení

Samostatně autorizované nasazení průvodce na potvrzený vlastní origin podle kapitoly o doméně. Případné související nasazení ticketingu pouze pro vstupenky.online, podle aktuálních pravidel lokálním buildem a `automation/deploy_direct.sh`. Ověřit veřejné URL a měření. První produktové a obchodní vyhodnocení po 4-6 týdnech nebo po získání dostatečného vzorku během sezony: zda lidé nacházejí relevantní plesy, kde hledání selhává, zda se vracejí, které stránky a oslovení přinesly kvalifikované pořadatele a spuštěný prodej, kde lidé tok opouštějí, kolik stojí údržba dat a mapa.

Teprve podle výsledku rozšiřovat geografii, SEO a případně Slovensko. Při problému lze stáhnout nové katalogové routy a zastavit import; existující prodej a objednávky běží dál. Nové datové tabulky se při rollbacku destruktivně nemažou.

## Rozsah a zbývající rozhodnutí

### Provozní odpovědnost před spuštěním

Určit jednoho vlastníka veřejných dat a jednoho vlastníka obchodních poptávek, případně stejnou osobu. Pracovní návrh pro pilot: pravidelná týdenní kontrola nadcházejících záznamů a dodatečná kontrola akcí pro nejbližší víkend; návrhy oprav ve frontě s viditelným stavem. Přesná kapacita a interval nejsou schválené SLA. Uložit datum a zdroj ověření, rozlišovat poslední import od posledního skutečného ověření. Zastaralé informace nedostanou automaticky nové datum kontroly.

Mimo sezonu ukazovat skutečně potvrzené další akce a odděleně zdrojově podložený výhled na další sezonu, vždy s odpovídající nejistotou. Vzhled se nesmí opírat o vymyšlené množství akcí, zaručeně vyprodané sály nebo vymyšlené reference. Pořadí výsledků v pilotu vychází z návštěvnické relevance; vlastní ticketing sám není důvodem skrýt vhodnější externí ples.

První verze nezahrnuje mobilní aplikaci, hodnocení, personalizovaná doporučení, newsletter, placené pozice ani automatické plošné scrapování. Hledání, kvalitní výsledky, mapa a důvěryhodný detail patří už do první funkční verze; vedlejší obchodní cesta je doplňuje. Stávající prodejní cesty zůstávají kanonické; žádná jejich náhrada ani odstranění není součástí tohoto záměru.

Před implementací rozhodnout podobu bezplatného zápisu, vybrat pilotní oblast podle dat a určit, kdo pravidelně ověřuje termíny a zpracovává návrhy a leady. Hlavní rizika jsou neaktuální ročníky, nedostatek potvrzených akcí mimo sezonu, práva k obrázkům a přivedení publika bez následné konverze pořadatelů. Proto se měření a obchodní cesta navrhují od začátku společně s katalogem.

Tato session mění pouze plánovací dokumenty. Neprovádí implementaci, zápis do Sheetů či produkční databáze, kontaktování pořadatelů, aktivaci placených služeb, commit, push ani nasazení.
