# Další integrační kanály a veřejná nápověda vstupenky.online

Datum: 2026-10-24
Stav: veřejná nápověda a Wix release kit implementovány k review; produkční nasazení nápovědy a veřejné Wix podání dosud neproběhly.

## Požadavek uživatele

Další platformu vybírat podle velikosti zákaznické základny a očekávaného
přínosu pro vstupenky.online. Součástí následující práce musí být veřejná
dokumentace nebo návodová sekce přímo na webu vstupenky.online.
Rozlišovat distribuovaný instalační doplněk a obyčejné vložení HTML kódu.

## Veřejné podklady ověřené 2026-10-24

| Platforma | Dostupná metrika | Omezení a distribuční cesta |
| --- | --- | --- |
| Wix | Přibližně 6,1 milionu premium předplatných skupiny k 31. 12. 2025; 4,2 % webů v říjnovém šetření W3Techs | Předplatné není unikátní zákazník ani pořadatel; skupinová metrika zahrnuje Base44. Skutečný App Market, kompatibilita závisí na editoru. |
| Shopify | Oficiálně miliony obchodníků ve více než 175 zemích | Globální e-commerce publikum; před vývojem určit požadovaný vztah k objednávkám a checkoutu Shopify. |
| Shoptet | Homepage uvádí 48 750 internetových obchodů | Počet obchodů není počet českých pořadatelů. Skutečný marketplace s obchodním a produktovým schvalováním partnerství. |
| Joomla | 1,1 % webů v témže říjnovém šetření W3Techs | Nemá srovnatelnou veřejnou metriku platících zákazníků; instalační rozšíření a katalog JED. |
| Webnode | Přes 50 milionů historicky vytvořených webů, z toho přes 3,7 milionu v ČR | Kumulativní historická čísla, nikoli aktivní zákazníci. Pro nás HTML embed a návod; nezaměňovat za katalogový doplněk. |

Zdroje:

- https://www.sec.gov/Archives/edgar/data/1576789/000162828026015222/wix-20251231.htm
- https://w3techs.com/technologies/comparison/cm-joomla%2Ccm-wix
- https://www.shopify.com/news/about-us
- https://www.shoptet.cz/
- https://www.webnode.com/press/
- https://dev.wix.com/docs/build-apps/launch-your-app/app-distribution/about-app-distribution
- https://www.webnode.com/support/using-third-party-plugins/
- https://extensions.joomla.org/support/knowledgebase/for-jed-developers/submitting-an-extension/
- https://blog.shoptet.cz/rozhovor-marketplace-tym/

## Doporučení a podmínky investice

Pro další katalogový doplněk prověřit nejprve Wix: větší webová základna než
Joomla a skutečný distribuční katalog. Je to doporučení podle dostupného dosahu,
nikoli doložený odhad návratnosti. Wix už nabízí vlastní Wix Events včetně
vstupenek, plánku a odbavení; před implementací popsat konkrétní důvod přechodu
pořadatele k naší službě a ověřit podporované editory, velikost widgetu,
scrollování, návrat z platby a aktuální podmínky publikace.

Pro český vstupenky.online nejprve dokončit samoobslužnou cestu WordPress a
obecné vložení včetně Webnode. Shoptet posunout výše při potvrzené poptávce
pořadatelů s existujícím e-shopem a ověřených podmínkách partnerství.
Shopify a Joomla zatím nepovažovat za automaticky schválenou investici.

Velikost platformy sama neurčuje návratnost. Chybí podíl pořadatelů,
instalace konkurence, cena získání zákazníka, aktivace a očekávaný výnos.
Rozhodnutí zpřesnit podle skutečných zájemců a jejich webových platforem.

## Veřejná dokumentace - povinný navazující rozsah

Navržený rozcestník: `https://vstupenky.online/napoveda/`.
Jde o návrh budoucí adresy; stránka tímto dokumentem nevznikla.
První verze má být součástí stávajícího veřejného webu, dostupná bez přihlášení,
s přímými odkazy na jednotlivé návody z doplňku a aplikace.

První obsah:

1. Začínáme: od účtu a akce k prvnímu zveřejněnému prodejnímu formuláři.
2. Vložení na vlastní web: výběr způsobu podle platformy.
3. WordPress: instalace ZIPu během čekání na schválení, nastavení a blok/shortcode;
   instalaci z katalogu popsat jako dostupnou až po skutečném schválení.
4. Webnode a obecný HTML embed: požadavky tarifu, vložení a publikace.
5. Běžné problémy: prázdný formulář, chybný odkaz, rozměry, vzhled a scrollování.
6. Aktualizace: živá služba versus vlastní aktualizace WordPress doplňku;
   již rozepsaný formulář se nesmí při vydání násilně obnovit.

Každý návod má uvést předpoklady, skutečně ověřené kroky a screenshoty,
očekávaný výsledek a řešení běžných chyb. Další CMS přidat po ověření jejich
skutečného publikovaného webu včetně mobilu, plánku, rekapitulace a výsledku.
Rozsáhlejší návody pro platby, vstupenky a odbavení rozšiřovat podle podpory.

## Další konkrétní práce

Nejdříve navrhnout a vytvořit veřejný rozcestník a ověřené WordPress/HTML návody.
Poté provést omezený průzkum Wix distribuce a widgetu, před plnou implementací
zhodnotit oslovené pořadatele a odlišení od Wix Events. V původním rozhodování ještě nebyl zadán vývoj dalšího marketplace doplňku;
navazující autorizace a výsledek jsou uvedeny níže.

## Upřesnění zadání: námaha 0 Kč a platba za prodané vstupenky

Uživatel výslovně nechce do priorit započítávat odhad vývojové námahy.
Nevymýšlet finanční ROI z odhadovaných rozpočtů nebo konverzí. Při nulovém
nákladovém základu není běžný poměr ROI definovaný. Pro rozhodnutí používat
dosah, vhodnost pro pořadatele, přípustnost stávajícího checkoutu a podíl
našeho příjmu, který zbude po poplatcích distribuční platformy.

### Požadované rozlišení peněz

Při schvalování předložit tento model: doplněk slouží jako obálka služby,
pořadatel platí podle prodeje vstupenek. Oddělit nominální hodnotu vstupenky
pro pořadatele, náš servisní výnos a náklady platební brány. Bez písemného
potvrzení neprezentovat celý obrat vstupenek jako výnos naší aplikace ani
neslibovat, že jej platforma ze základu své provize jistě vyloučí.

Příklad pouze pro vysvětlení: vstupenka 1 000 Kč, náš servisní poplatek 50 Kč.
Požadovaný základ marketplace provize je 50 Kč; 20 % z takového základu je
10 Kč. Pokud by byl základem celý obrat 1 000 Kč, poplatek 200 Kč přesahuje
náš servisní výnos. Tento rozdíl musí být výslovně vyřešen před publikací.

### Zjištěné podmínky a otevřené otázky

- Wix, partner agreement účinný od 30. 6. 2026, § 9.3: standardně 20 %
  z Net App Revenues po prvních 12 měsících od uvedení aplikace; první rok
  podíl 0 %. U Partner Billed Apps se podíl vztahuje i na další související
  příjmy. Transakční poplatek 2,5 % platí pouze při účtování přes Wix.
  Externí účtování potřebuje písemné schválení. Nelze předpokládat, že je
  zdarma tím, že samotná instalace doplňku stojí 0 Kč.
  - https://dev.wix.com/app-market-partner-agreement
  - https://dev.wix.com/docs/build-apps/launch-your-app/pricing-and-billing/report-revenue-for-partner-billed-apps
- Shopify, App Store requirements § 1.1.2 a § 1.2: katalogová aplikace nesmí
  obcházet Shopify checkout; app charges se účtují přes Shopify nebo podle
  schválené výjimky. Současný externí checkout nelze automaticky nabídnout
  jako stejnou obálku z WordPressu. Revenue share app billing je oddělený
  od plateb za zboží a jejich zpracování. Oficiální App Revenues definice je
  široká; konkrétní servisní poplatek a jeho účtování je nutné potvrdit.
  - https://shopify.dev/docs/apps/launch/shopify-app-store/app-store-requirements
  - https://www.shopify.com/partners/terms
  - https://shopify.dev/docs/apps/launch/distribution/revenue-share
- Shoptet: existuje veřejně nabízená integrace pro vstupenky s měsíční cenou
  doplňku a další provizí poskytovatele za prodané vstupenky. Je to doklad
  existujícího modelu, nikoli závazná nabídka ani sazba Shoptetu pro nás.
  Potřebujeme konkrétní smluvní nabídku: poplatek/odvod platformě, jeho základ,
  povolený checkout, storna a vztah stávajících zákazníků k novým instalacím.
  - https://doplnky.shoptet.cz/rezervacni-system
  - https://eshop-booking.cz/
  - https://doplnky.shoptet.cz/chcete-delat-vlastni-doplnky
- Webnode HTML embed nepředstavuje publikaci aplikace v marketplace. Provozovatel
  webu může potřebovat placený tarif; nejde o provizi z našich vstupenek.
- U Joomla JED nebyl v prozkoumaných veřejných postupech nalezen publikační
  poplatek ani podíl z příjmu. Absence veřejné sazby není samostatné písemné
  potvrzení všech podmínek našeho konkrétního modelu.

### Co je skutečně zajištěno

Byly ověřeny veřejné podmínky a sepsány rozhodovací otázky. Wix ani Shoptet
zatím nevydaly individuální potvrzení našeho peněžního toku. Neproběhla žádná
externí komunikace ani přijetí nové partnerské smlouvy. Před závazkem získat
písemné potvrzení konkrétního modelu, nevyvozovat je jen z označení free app.

### Aktuální pořadí práce bez nákladů na vývoj

1. Veřejná nápověda, WordPress onboarding a ověřený HTML/Webnode embed.
2. Wix: první další globální marketplace kandidát, nejprve potvrdit základ
   podílu, externí billing a zachování ticket checkoutu.
3. Joomla: samostatný lehký doplněk jako další distribuční kanál.
4. Shoptet: posunout výše po přijatelné smluvní nabídce pro český trh.
5. Shopify: samostatný model nativního prodeje přes Shopify checkout; současnou
   externí checkout obálku nepublikovat jako automaticky přípustnou aplikaci.

## Potvrzená etapa a stav implementace

Uživatel následně výslovně zadal veřejnou dokumentaci a obecné vložení,
Webnode kvůli dohledatelnosti, WordPress s doplňkem i bez něj a paralelní
přípravu Wix vydání subagentem.

Připraveno šest veřejných stránek pod `/napoveda/`, HTML generátor s validací
odkazu a automatickou/pevnou výškou, přesný WordPress ZIP, SEO metadata,
sitemap a navigace. Zdroj: `automation/release/help/`. Webové a cílené
automatizované kontroly prošly; 320px světlý a desktopový tmavý vzhled byly
ověřeny v izolovaném prohlížeči. Generátor nenačítá checkout.

Subagent dodal `integrations/wix/`: self-managed Site Widget (Custom Element),
settings panel s pinned Wix SDK a explicitní release gate. Sedm testů a build
prošly. Veřejné vydání čeká na skutečná Wix ID, hosting, písemné schválení
platebního modelu a ověření v reálných editorech. Nebyla přijata smlouva ani
odesláno veřejné podání.

Změny jsou připravené v PR https://github.com/festappnet/festapp/pull/587.
Main vyžaduje schvalující review; produkční nasazení této etapy dosud neproběhlo.
