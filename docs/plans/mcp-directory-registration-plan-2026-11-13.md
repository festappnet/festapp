# Registrace MCP produktů pod vydavatelem Festapp

> Realizační zadání: [exekuční prompt](mcp-directory-registration-EXECUTION-PROMPT-2026-11-13.md)
> rozšiřuje tento návrh o vydání až do ověřeného produkčního výsledku. Vyžaduje
> kanonické opravy sdílené s produkční aplikací, migraci všech dotčených volajících,
> odstranění nahrazených větví a testy MCP i odpovídajících aplikačních cest.
> Rozsah realizace a oprávnění při jeho spuštění určuje toto novější zadání.

Datum: 2026-11-13  
Stav: Plán pro realizaci; veřejné registrace zatím neprovedeny  
Ověřování: standard pro veřejné kontrakty, OAuth a provoz; bez testů pouze kvůli sepsání plánu

## Změna zadání: globální připojení Festapp

Pozdější rozhodnutí z 2026-11-13 nahrazuje globální MCP identitu **Festapp Tickets**
identitou **Festapp**, která pokrývá celou aplikaci včetně ticketingu. Závazné
pořadí je nejprve připravit a ověřit globální endpoint podle
[navazujícího návrhu](festapp-global-mcp-endpoint-plan-2026-11-13.md), potom
realizovat registrace **vstupenky.online** a **Festapp**. Níže uvedené požadavky
na samostatný globální záznam, metadata a ověření platí pro Festapp. Historické
zmínky o Festapp Tickets v evidenci označují ticketingový produkt, ne požadavek
na třetí duplicitní MCP registraci. Vydavatel zůstává Festapp.

## Výsledek a rozsah

Jeden vydavatel **Festapp**, dvě samostatná připojení **vstupenky.online** a **Festapp**. Každý má vlastní identitu záznamu a připojení, pravdivý popis, dokumentaci a ověřený endpoint. Sdílená implementace není důvod kopírovat server ani vydávat regionální připojení za globální produkt.

Cílem je co nejlepší doložená způsobilost a dohledatelnost v relevantních katalozích. Pořadí, odznak, přijetí ani počet uživatelů nelze slíbit. Plán nezavádí placenou propagaci, nové platební funkce ani hromadný rollout tenantů. Požadavek sestavit plán sám neznamená provedenou registraci nebo schválení externím katalogem.

## Zjištěný stav

| Fakt a zdroj | Dopad |
|---|---|
| `CLAUDE.md`, Platform brand: Festapp / Festapp Tickets / vstupenky.online | Přesné názvy používat ve všech profilech. Festapp je vydavatel, nikoli třetí duplicitní produkt. |
| `integrations/chatgpt/README.md`, `tools/festapp/README.md`: regionální MCP `https://mcp.vstupenky.online/mcp`; starý host mcp.festapp.net vyřazen s 410 | Publikovat regionální endpoint. Starý host nepoužívat jako regionální alias. Jeho případné nové globální využití řídí navazující návrh; aktuální dostupnost ověřit před podáním. |
| `integrations/chatgpt/review/readiness.md`: poslední doložený stav 2026-11-05 je In review / Not published | Netvrdit schválení ChatGPT; registrace do katalogů je jiný proces. |
| `LICENCE`: MIT, původní copyright 2023; veřejný GitHub rozpoznává MIT | Nezavádět novou licenci ani nepřepisovat držitele práv. Doplnit chybějící metadata teprve po ověření rozsahu. |
| `tools/festapp/package.json`: private:true, bez license; sdílený operátorský nástroj | Není potřeba zveřejnit npm balíček pro registraci remote serveru. Licence hlavního projektu neprokazuje licence závislostí. |
| `automation/release/tenants/festappticketsglobal.manifest.json`: globální tenant má release-pending, hostnameApproved:false | Globální endpoint a veřejná připravenost nejsou doložené. Před realizací ověřit novější stav; nezveřejnit nefunkční druhý produkt. |
| `integrations/chatgpt/plugin.json`: Festapp, info@festapp.net, existující logo, odkazy na podporu, soukromí a podmínky | Znovu využít schválené údaje; metadata pro jiný klientský profil musí odpovídat jeho skutečnému rozsahu. |

## Registry a jejich pořadí

1. **Official MCP Registry - priorita 1.** Publikovat dvě oddělené identity postupně podle připravenosti. Podporuje remote-only `server.json` s `remotes` typu `streamable-http`, bez `packages` a bez npm publikace. Namespace se ověřuje; kontrola namespace sama neprokazuje vlastnictví remote URL. Krátký description má podle ověřeného quickstartu limit 100 znaků. Autoritativní postup: [quickstart](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/quickstart.mdx), [ověření namespace](https://github.com/modelcontextprotocol/registry#authentication). Hledání [festapp](https://registry.modelcontextprotocol.io/v0.1/servers?search=festapp) a [vstupenky](https://registry.modelcontextprotocol.io/v0.1/servers?search=vstupenky) nevrátilo záznam. Nejde o důkaz absence pod jinou identitou.
2. **Glama - priorita 1.** Ověřit vhodnou cestu pro [remote connectors](https://glama.ai/mcp/connectors) a vlastnictví profilů; samostatně posoudit [katalog serverů](https://glama.ai/mcp/servers). Založit či převzít skutečné produktové záznamy, propojit veřejný repozitář a doložit licenci. Nezakládat duplicitní katalogové záznamy kvůli klíčovým slovům. Podle [oficiálního FAQ](https://glama.ai/mcp/faq) je cesta Connectors → Add Server → Hosted endpoint: název, krátký popis, veřejné HTTPS streamable-http URL. Pouze healthy konektory se indexují. Health check inicializuje spojení a načítá metadata, nástroje nespouští. Pro OAuth použít privátní testovací profil s oddělenou identitou a minimálními právy, bez zákaznických dat. Po claimu nastavit skutečnou autentizaci v Admin → Test Profile. Claim podporuje DNS `_glama-claim.<domain>`, `https://<domain>/.well-known/glama.json`, endpoint proof nebo GitHub identitu; pro organizaci GitHub cesta vyžaduje instalaci Glama GitHub app. Preferovat ověření domény před udělením přístupu aplikaci do organizace, pokud poskytuje stejný potřebný výsledek. Repo-based open-source cesta hodnotí licenci, security a health a podporuje glama.json; její hodnocení nelze automaticky přenést na remote konektor. Před skutečným podáním znovu ověřit případné změny pravidel.
3. **PulseMCP - sledovaná návaznost.** [Submit](https://www.pulsemcp.com/submit) při průzkumu uvádí dočasně pozastavený příjem nových záznamů a úprav a plán převzetí z Official Registry po obnovení. První krok je tedy oficiální záznam; následně ověřit skutečné převzetí, nikoli předpokládat okamžité zařazení. Stránka aktualizovaná 2026-09-03 jako důvod uvádí přepracování directory pipeline a správy záznamů pro přesnost a rychlejší změny; práce trvá déle, než očekávali, termín obnovení neuvádí. Nejde o doložený incident ani problém konkrétního serveru.
4. **MCP.so - doplňkově.** [Submit](https://mcp.so/submit) přijímá i hostovaný endpoint. Při realizaci prověřit bezplatnou cestu a aktuální podmínky. Zjištěná placená nabídka $39 není autorizovaným výdajem; bez výslovného souhlasu ji nepoužívat. Bezplatné podání má nižší prioritu než správná integrace do prvních dvou registrů.
5. **Smithery - zatím odloženo.** Při průzkumu oznámil konec proxy a managed identity k 31. říjnu a přechod pod Arcade. Před případným zařazením znovu ověřit aktuální produkt, katalog a podmínky. Nespoléhat na dřívější hostingovou nabídku.

Nejde o pořadí podle ověřené návštěvnosti; ta nebyla měřena. Jde o doporučené pořadí podle funkce oficiálního registru, vhodnosti remote katalogu a současné dostupnosti podání.

## Identita, licence a kvalitativní podmínky

- Preferovat oba technické názvy pod jedním ověřeným namespace vydavatele, například `net.festapp/vstupenky-online` a `net.festapp/festapp`. Jde o návrh, nikoli rezervované názvy. Nejprve ověřit dostupnost, přesnou syntaxi a kontrolu domény; pokud katalog pracuje s účtem vydavatele místo namespace, použít tentýž účet Festapp. Zobrazované názvy zachovat přesně podle značek.
- Právního provozovatele převzít z aktuálních schválených podmínek; Festapp jako značka nesmí vytvářet smyšlenou právnickou osobu. Podpora `info@festapp.net`, web, produktové logo a vazba na platformu musí být konzistentní.
- Licence kódu, licence závislostí, práva ke značce a podmínky hostované služby jsou různé věci. Ověřit působnost MIT pro publikované MCP zdroje, zachovat `LICENCE` i historické copyrighty. Doplnění `license: MIT` do tools/festapp/package.json musí odpovídat skutečnému právnímu rozsahu; nevymýšlet odlišné podmínky ani automaticky měnit private:true.
- Pro produkčně používané přímé i tranzitivní závislosti a přibalená aktiva připravit soupis verzí, SPDX licencí, požadovaných oznámení a výjimek. Vycházet z přesného lockfilu a skutečných balíčků, ne z odhadu podle názvu. Silný copyleft, chybějící licence či nejasná práva mají konkrétní záznam a rozhodnutí před distribucí dotčeného artefaktu. Nenahrávat celý repozitář kvůli badge a nerozšiřovat audit na nesouvisející aplikace.
- Veřejná dokumentace má uvádět transport, endpoint, podporované klienty, konkrétní připojení, oprávnění, požadovaný účet, dostupnost/cenu, odvolání přístupu, známá omezení, podporu a ukázky. Anglické katalogy mají přirozený anglický popis; český produkt jasné regionální vymezení. Ukázky a screenshoty pouze se syntetickými, lokalizovanými daty; screenshoty v light mode.
- Popis musí vycházet z aktuálního nástrojového katalogu a klientského profilu. Veřejný ChatGPT profil `order-summary` nevypovídá o automatické dostupnosti pro jiné klienty. Není dovoleno inzerovat zápisy, rezervace, nákup vstupenek nebo veřejné vyhledávání akcí, pokud je dané připojení nedokládá.
- Relevantní kategorie a hledané výrazy: ticketing, event management, event organizers, sales reports, order status; české vstupenky a prodejní přehledy tam, kde katalog jazyky podporuje. Přesná značka v titulku, konkrétní přínos v první větě, použitelné příklady. Žádné keyword stuffing, falešné recenze nebo tvrzení official/verified bez potvrzení katalogu.
- Statická klientská registrace je současný fakt; katalogový testovací klient nemusí být kompatibilní. Ověřit skutečnou podporu OAuth/PKCE, přesné callbacky a veřejný profil před inzerováním one-click připojení. Nevypínat autentizaci, nezapínat plošné DCR ani nerozšiřovat scopes kvůli katalogovému skeneru.

## Realizační vlny

### 1. Uzavřít evidenci a připravenost

Vytvořit `integrations/mcp-directories/README.md` a strojový přehled produktů se společným vydavatelem: namespace, zobrazované názvy, skutečné endpointy, zdrojový repozitář, podpora, právní URL, stav připravenosti a katalogové identity. Sekrety ukládat výhradně do chráněných úložišť podle AGENTS.md. Globální stav ověřit proti novější evidenci a runtime, nikoli jen historickému manifestu. Každé neověřené pole výslovně blokuje podání příslušného produktu; není náhradním endpointem.

Výstup: doložená matice připravenosti pro oba produkty, potvrzení aktuálnosti výše doložené cesty podání Glama a zvolená metoda claimu. Ověření: primární stránky registrů a veřejné odkazy, bez změny produkce.

### 2. Doplnit metadata, dokumentaci a licenční doklady

Připravit veřejné CS/EN produktové podklady a dva manifesty pro registr tam, kde schéma vyžaduje samostatný manifest. Umístění `integrations/mcp-directories/`, společná data neduplikovat ručně mezi registry. Doplnit licenční metadata po ověření působnosti, připravit seznam závislostí a oznámení; zachovat schválená loga pod `assets/brand/`. Stávající ChatGPT balíček neměnit jen kvůli jinému katalogu.

Výstup: vyplněné regionální podání bez placeholderů; globální podání se finalizuje až se skutečným endpointem. Ověření: aktuální oficiální schema, kontrola délek a URL, kontrola licenčních dokladů. Pokud se publikují zdrojové změny, použít postižené kanonické CI lanes z `automation/test_ci.sh` dle CONTRIBUTING.md.

### 3. Ověřit připojení a podat regionální produkt

V prostředí se syntetickou reviewer identitou ověřit discovery, OAuth/PKCE, nejméně jeden reprezentativní výsledek, omezení na vybrané akce, odmítnutí nepovoleného přístupu a revokaci. Znovu použít relevantní existující MCP testovací scénáře z `tools/festapp/test/` a `integrations/chatgpt/review/`; nevytvářet reálné objednávky. Pokud katalog pouze indexuje URL, nepřidávat klienta zbytečně. Pokud potřebuje klienta, přesné požadavky vyřešit podporovanou registrací a profilem, ne obejitím zabezpečení.

Po autorizaci veřejné realizace publikovat nejdříve do Official Registry pomocí aktuálního mcp-publisher, pak do Glama. Před každým podáním hledat již existující identitu a aktualizovat ji; retry nesmí vytvořit duplicitní záznam. Uložit sanitizované potvrzení, ID, veřejné URL, datum a stav submitted/approved/live/rejected odděleně. Nepovažovat odeslání za zveřejnění.

Výstup: veřejný regionální záznam, správný vydavatel, funkční odkaz na připojení a doložený stav Glama. Externí schvalování s neurčeným termínem zaznamenat jako čekající, nikoli dokončené.

### 4. Dokončit samostatný globální Festapp záznam

Podmínkou je skutečný schválený globální endpoint, odpovídající tenant/client binding, právní a podpůrné stránky a vlastní syntetická demonstrace. Nepoužít regionální endpoint jako náhradu ani neoprávněně spustit release globálního tenantu. Pokud je ke splnění nutný vývoj, DNS nebo produkční nasazení, rozepsat přesnou změnu a použít pravidla příslušného release; rutinní deploy delegovat dle AGENTS.md. Publikovat pod stejným vydavatelem, s odlišnou identitou a pravdivým globálním popisem, a zopakovat cílené ověření z předchozí vlny.

Výstup: druhý živý záznam; žádná záměna produktu, dat či OAuth prezentace.

### 5. Doplnit další distribuci a ověřit dohledatelnost

Zkontrolovat obnovu PulseMCP a skutečné převzetí z oficiálního registru. Využít bezplatnou cestu MCP.so, pokud je dostupná a vhodná. Porovnat veřejný výsledek s podanými metadaty: přesný název, vydavatel, URL, licence, kategorie, popis, logo a uvedená kompatibilita. Změřit dohledání přes přesné názvy a několik relevantních dotazů; zaznamenat datum a pozici bez slibu trvalého pořadí. Neprovádět placené boosty. Aktualizace katalogů navázat na vydání produktu; automatické plánované kontroly zakládat pouze na samostatný požadavek.

## Provozní pravidla, validace a dokončení

Browser práci delegovat na Terra, použít vlastní tiché/background relace, žádné zásahy do uživatelových tabů. Nové registry účty pouze při autorizované realizaci; před žádostí o heslo prohledat relevantní chráněná úložiště podle AGENTS.md. Neposílat provozovatelům katalogů emaily ani zprávy bez explicitního pokynu. Platební nabídky nejsou součástí autorizace.

Nasazení, pokud je potřeba, jen pro konkrétní zvolený tenant, s lokálním buildem, direct deployment a přesnou kanonickou CI release gate. Počet Flutter úloh nejvýše jedna, testy s concurrency=1. Zápisy do registru nevyžadují preventivní Flutter build.

Chybný katalogový údaj opravit na existujícím záznamu. Uniklé citlivé údaje odstranit a řešit jako skutečný incident; katalogová chyba není důvod vracet starý endpoint nebo měnit oprávnění uživatelů. Historická schvalovací evidence se nemaže.

Hotovo znamená dva pravdivé a odlišené produktové záznamy pod Festapp v cílových dostupných registrech, doložené licence a oznámení, funkční připojení deklarovaných klientů, veřejně ověřené výsledné URL a stav každého podání. Nedostupný registr, chybějící globální endpoint nebo čekající moderace zůstávají pojmenovanou nehotovou položkou. Hlavní zbytková rizika: externí moderace a změny pravidel, kompatibilita statického OAuth s klienty katalogů a nedoložená aktuální globální připravenost.
