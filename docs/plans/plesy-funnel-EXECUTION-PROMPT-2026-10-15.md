# Exekuční prompt: prémiový přehled plesů

Implementuj veřejný přehled plesů pod pracovní značkou Plesuj, propojený se vstupenky.online v repozitáři `/Users/miakh/source/festapp` podle autoritativního plánu:

`docs/plans/plesy-funnel-plan-2026-10-15.md`

Přečti jej celý spolu s AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Jde o zadání pro budoucí implementační session; jeho příprava neznamená, že byla realizace nebo produkční změna právě provedena. Pokud uživatel omezí session na prototyp nebo jinou fázi, dodrž tento užší rozsah.

## Výsledek

Vytvoř vizuálně propracovaný, primárně tmavý a elegantní průvodce pro lidi, kteří chtějí najít a vybrat ples podle místa a termínu. Součástí je mapa s kvalitním českým podkladem, rychlé mobilní hledání, důvěryhodné detaily a dohledatelnost v běžných i AI vyhledávačích. Akvizice pořadatelů je vedlejší obchodní cesta, nesmí rušit hledání. Vlastní vstupenky vedou přímo na existující prodejní formulář, ostatní akce na stránku pořadatele s informacemi o nákupu či rezervaci. AI chatbot do rozsahu nepatří.

Použij marketingové sdělení a SEO texty z plánu, pracovní značka „Plesuj“, výchozí H1 „Najděte svůj příští ples.“ Rozsah tvrzení přizpůsob skutečnému pokrytí pilotu. „Největší český přehled plesů“ je zatím ambice, ne doložený claim; bez srovnávací evidence jej nepublikuj. CRM řádky, archiv a odhady nejsou počet aktuálních potvrzených plesů.

Pracovní doporučení je samostatná doména plesuj.cz, nikoli subdoména nebo původně navržená sekce. Přečti i `docs/plans/plesuj-market-scan-2026-10-15.md`. Potvrď cílový origin před implementací URL kontraktu. Katalog má jedinou kanonickou podobu; prodej a přihlášení zůstávají na vstupenky.online. Nepřepisuj globální WEB_LINK ticketingu ani nevytvářej bez zadání druhý tenant, další produkční větev nebo auth. Doména nebyla koupena a její dostupnost i případné kolize názvu je nutné ověřit před spuštěním.

## Začni daty, nevymýšlej potvrzené akce

Použij read-only SQLite `~/.local/share/festapp/plesy-research/prospects.sqlite3` a audit `docs/plans/plesy-funnel-sqlite-audit-2026-10-15.json`. Audit zachycuje snapshoty z 8. října, nikoli dnešní veřejné potvrzení. Znovu zkontroluj aktuální snapshot metadata, pokud od auditu přibyla data. `records.data` je u importovaných řádků JSON pole, mapuj jej přes `snapshots.header` pro příslušný `sheet_id`. Nezaměňuj normalizované vyhledávací názvy za původní veřejné názvy. Archivní pozorování nepřičítej k počtu unikátních plesů.

Rozděl pořadatele, konkrétní plesy a ročníky. Jeden řádek může obsahovat více akcí, historii i další sezonu. V pilotu ověř zdroje a doplň především identitu akce, aktuální konání/termín, obec a sál, způsob prodeje a zdroj každého tvrzení. Obnov neúplné zdrojové odkazy z podkladů, nebo je znovu dohledávej. Kontakty a interní obchodní data nezveřejňuj.

Povinně implementuj dvě nezávislé osy: jistotu konání `announced/reported/inferred/unknown` a přesnost termínu `day/month/range/season/unknown`, podle kapitoly o nejistotě. Například:

- Potvrzený den: „23. ledna 2027“.
- Oznámený měsíc: „Leden 2027 - přesný termín ještě není zveřejněný“.
- Odhad: „Očekáváme v lednu 2027 - ročník zatím nepotvrzen“, s vysvětlením historického podkladu.

Odhad nového ročníku smí být veřejně viditelný, musí však být jasně označený už na kartě. Přesné datum pouze z kalendáře kapely není automaticky potvrzeným dnem. Jediný starý ročník nedokládá každoroční opakování. Nepřenášej do nového ročníku cenu, místo, dostupnost ani starý prodej. Očekávaný měsíc nesmí vytvořit falešné datum ani výsledky na každý víkend. Zohledni pohyblivé svátky a po uplynutí odhadu jej automaticky neposouvej.

## Povinný design workflow

Načti a použij `/Users/miakh/.codex/skills/ui-ux-pro-max/SKILL.md` z GitHub projektu nextlevelbuilder/ui-ux-pro-max-skill, revize a provenance jsou uvedené v plánu. Kanonická lokální kopie je v `/Users/miakh/source/development-tools/vendor/codex-skills/ui-ux-pro-max/`. Použij i stávající ux-designer.

Před návrhem proveď relevantní design-system a cílené UX rešerše. Automatický výsledek kriticky posuď podle briefu; nepřejímej světlou marketingovou šablonu, Liquid Glass ani změnu stacku. Připrav tři stručné tmavé vizuální směry na stejném obsahu a rozpracuj vybraný do desktopu i mobilu. Pokud uživatel výběr deleguje, použij jako výchozí večerní editorial z plánu. Lokální koncepty jsou self-contained statické HTML bez serveru; nepředstírej funkční mapové napojení, pokud jde jen o ukázku.

Návrh musí řešit také očekávané ročníky, chybějící fotografii/cenu, prázdné výsledky, načítání, chyby a návrat z detailu. Samotný pěkný úvod ani uvedení skillu mezi odkazy není dokončený design. Zachovej tenantovou značku a funkční společnou hlavičku.

## Realizace a ověření

Postupuj po vlnách plánu: datový pilot, vizuální návrh, funkční katalog s mapou a vedlejší konverzní cestou, samostatně autorizované spuštění. Použij kanonický backend, stávající vanilla JS/Vite klient, bootstrap, organizační intent a prodejní formuláře. Nepřidávej druhý auth nebo prodejní systém. SQL a veřejný datový kontrakt patří do kanonických repository souborů a řízených migrací.

Dokonči seznam a mapu se společnými filtry, potvrzené termíny pro přesné víkendy, oddělený sezonní výhled a stabilní profily opakujících se plesů. Doplň čitelné HTML, lokální a víkendové SEO vstupy v rozsahu pilotu, canonical, sitemap a rozumnou indexaci filtrů. Odhady se v title, textu a náhledu označují stejně; nevkládají se jako `Event.startDate`, nabídka vstupenek ani kalendářová pozvánka. Schéma Event použij pro doložené konkrétní termíny, ne jako falešné potvrzení očekávání. Citace v AI ani rozšířené výsledky nejsou garantované.

Cílené kontroly musí ověřit publikaci/oprávnění, opakovatelný import, oddělení historie a očekávání, změnu odhadu na potvrzený stejný ročník, konfliktní a zastaralé podklady, víkendy přes hranice roku, shodu seznamu a mapy, datum/nejistotu v HTML i metadatech a absenci interních polí v anonymní odpovědi. V jedné přiměřené browserové dávce ověř mobil, desktop, ovládání, kontrast a cestu ke vstupenkám. Plánování/prototyp low-risk; veřejné kontrakty, oprávnění a migrace standard. Nepřidávej testy jen pro kontrolu textu dokumentů a neopakuj passing checks bez změny vstupů. Další agenty nespouštěj bez výslovného zadání.

## Hranice oprávnění a předání

Tento prompt neopravňuje k oslovování pořadatelů, automatické aktivaci placených služeb ani zápisu do CRM. Produkční migrace, deploy a Git publikaci prováděj pouze pokud je zadání session autorizuje. Případný deploy průvodce na vlastní doménu vyžaduje vyřešený host routing podle plánu a autorizaci příslušné session. Související deploy ticketingu platí jen pro vstupenky.online, lokálním buildem a přímým deployem podle aktuálních pravidel repozitáře. Zachovej nesouvisející změny pracovního stromu; pro implementaci podle potřeby použij čisté worktree.

Pokud aktuální evidence vyvrátí premisu plánu, oprav ji a přizpůsob dotčenou fázi, aniž by se změnily potvrzené priority. Při předání uveď hotové chování, skutečné počty zpracovaných entit podle jistoty, provedené ověření a přesné zbývající kroky. Nenazývej prototyp hotovým portálem ani počet řádků počtem potvrzených plesů.
