# Aktuální rozhodnutí: pouze serverové souhrny bez lišty

Uživatel výslovně zvolil „jen serv. bez listy“. Tato část nahrazuje níže
uvedená dřívější zadání RUM, veřejných SPA tras, referrerů a cookie opt-out.
Historické důkazy níže nejsou popisem současného sběru.

## Provedeno na produkci

- Pouze host `vstupenky.online`; ostatní hosty a tenanty beze změny.
- Configuration Rule `a7ded3d36099492287f5c9820fbf8feb` přejmenováno na
  `Disable browser analytics on vstupenky.online`.
- Nová expression: `(http.host eq "vstupenky.online")`.
- Jediná akce zůstává `set_config`, `disable_rum: true`; pravidlo je Active.
  Ověřeno uložené pravidlo i text „The Web Analytics performance beacon is disabled“.
- Web Analytics site/history ponechány, ale automatická injekce je pro tento
  přesný host přebitá Configuration Rule. Žádný manuální beacon ani nový collector.
- Neaktivovala se placená služba, žádný vlastní event/funnel/SQL/Edge Function.
- Ve skutečném Chrome odstraněna pouze již nepotřebná host-only cookie
  `festapp_analytics_optout` s Path=/; přihlášení ani ostatní cookies se neměnily.

## Ověření skutečného účinku

Izolovaný headless Chrome s explicitním DNS mapováním CDN (bez lokálního
DNS blokátoru), bez opt-out cookie: na `/` i `/scan` je beaconScripts=0,
initialized=false, resources=0. Po syntetickém history.pushState na
`/scan/SYNTHETIC_PRIVACY_CHECK` a `/organizationEdit/3` totéž; seznam
síťových požadavků filtrovaný na rum je prázdný. Testovací kód není skutečná
capability a nebyla vyvolána žádná objednávková ani administrační mutace.
Také skutečný uživatelův Chrome po načtení nové karty: žádný beacon ani
inicializace. Již otevřené starší stránky je nutné jednou obnovit.

## Přehled serverového provozu

Ověřen živý přehled Requests se skutečnými daty a zeměmi Czech Republic
+ další EU. Přehled omezen filtrem Host equals vstupenky.online:

https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/vstupenky.online/analytics/requests?filters=%5B%5B%7B%22key%22%3A%22clientRequestHTTPHost%22%2C%22operator%22%3A%22eq%22%2C%22value%22%3A%22vstupenky.online%22%7D%5D%5D

Jde o požadavky včetně souborů, botů, scanneru a administrace, nikoliv
čisté počty veřejných návštěvníků. Nevykazuje pohyb uvnitř Flutteru bez
HTTP požadavku ani browserové Core Web Vitals. Dřívější cookie opt-out
serverové požadavky nevylučuje. Zdroje návštěv nejsou slibovanou funkcí
aktuálního základního přehledu. Jemnější členění závisí na tarifu; žádný
upgrade nebyl objednán.

## Rozsah soukromí a oprávněného zájmu

Nové čtení browserových API, analytické cookies ani přenos SPA tras do RUM
jsou vypnuté. Serverový provoz nelze označit za zcela anonymní: Cloudflare
při obsluze nutně přijímá IP, HTTP cestu a technické údaje požadavku a
jeho dashboard může obsahovat i IP a cesty. Nevytváříme k nim nové kopie,
identifikátory ani propojení s účty/objednávkami. Účel souhrnů je provoz,
kapacita, dostupnost a bezpečnost, nikoliv marketing/profilování uživatelů.
Volba méně invazivního serverového přehledu odstranila pro tento úkol
potřebu browserového měření; zůstává povinnost transparentně informovat
o serverovém zpracování a řešit případné námitky. Nejde o audit veškerého
ostatního zpracování aplikace, např. dříve existujícího měření e-mailů.

Lokálně upraven odkaz v Organization Edit a popisky v šesti jazycích na
serverový provoz. Zásady soukromí a volby nyní popisují skutečný režim,
neobsahují slib účinného cookie opt-out. Tyto změny aplikace a dokumentů
nejsou dosud vydané; živé vypnutí RUM proběhlo bez deploye aplikace.

Validace lokálních změn: renderer právních stránek a jeho --check prošly.
Cílený `fvm dart analyze lib/components/organization/views/organization_edit_page.dart`
skončil kódem 0, pouze již existující info o názvu konstanty ROUTE (řádek 20).
Obě prohlížečové session byly po ověření uzavřeny. Žádný app deploy,
commit ani push neproběhl.

Podklady:
https://developers.cloudflare.com/rules/configuration-rules/settings/
https://developers.cloudflare.com/analytics/account-and-zone-analytics/zone-analytics/

---

## Historie dřívějšího zadání a kontrol (nahrazeno rozhodnutím výše)

# Cloudflare analytika veřejné části vstupenky.online

Datum: 2026-10-20
Stav: pouze veřejný web client; po výslovné autorizaci 2026-10-20 je výjimka EU vypnutá v Cloudflare.
Verification: standard pro změny produkční konfigurace a veřejného sběru.

## Aktuální zadání

Měřit pouze veřejnou část `web_clientu` na přesném hostu `vstupenky.online`
pomocí Cloudflare Web Analytics. Přehled statistik zůstává v Cloudflare.
Žádný analytický panel v aplikaci, Edge Function pro čtení statistik,
SQL migrace, vlastní collector, IP logování ani další tenant.

Uživatel následně výslovně zvolil pouze souhrnné zdroje návštěv.
Využít existující dimenzi Referer v Cloudflare; žádné přiřazování zdroje
k objednávce, nové identifikátory návštěv ani vlastní konverzní funnel.

Toto upřesnění nahrazuje dřívější požadavek na Organizational Admin a čtení
7/30 dní přes nový backend. Během realizace připravený admin panel, model,
service adapter, Edge Function, jejich testy a přidané překlady byly odstraněny.
Stávající cizí rozpracované změny byly zachovány. Odstraněné testy nejsou
součástí výsledného řešení a jejich průchod se nesmí vydávat za jeho ověření.

## Ověřený výchozí stav před změnou EU režimu

- Tenant `festapptickets`, jediná cílová větev `prod/festapptickets`, Pages projekt
  `vstupenkyonline`. Živý activation dokument potvrzuje canonical backend,
  generation 1. V canonical databázi organizace 3 odpovídá vstupenky.online.
- Cloudflare účet `84b32318ac235bf6738bdf1c8caa0795`.
- RUM site `4b64cee2415d4110b11abc4d56013278`, vytvořený
  `2026-08-28T20:38:42.917798Z`. Čas vytvoření není doložený začátek sběru.
- Ruleset `1ecf61ab-efc1-4753-a2ba-c0ea84c9d1d1`:
  `auto_install=true`, `enabled=true`, `lite=true`.
- Jediné pravidlo `3001017b-7ba9-4730-8dcd-bfefc825cf6a`:
  `host=*`, `paths=["*"]`, `inclusive=true`, `is_paused=false`.
- Cloudflare UI potvrzuje zvolenou možnost
  `Enable, excluding visitor data in the EU`. EU je tedy nyní vyloučena.
  [Dokumentace parametru lite](https://developers.cloudflare.com/api/terraform/resources/rum/).
- Stažené homepage HTML neobsahuje beacon script; tento výsledek z EU není
  důkaz globálně vypnutého sběru. Pages API nemá vlastní web analytics tag/token;
  současnou injekci vlastní RUM konfigurace zóny.
- Uživatel následně výslovně autorizoval naklikání přístupu v otevřeném Chrome.
  Vznikl token `Festapp vstupenky analytics read`, pouze
  `Account Settings Read` a `Account Analytics Read`, omezený na daný účet.
  Je uložen mimo repozitář v chráněném lokálním souboru s právy 0600;
  hodnota nebyla vypsána do chatu. Žádný serverový secret nebyl vytvořen.
- Token skutečně úspěšně přečetl site, rules i RUM data. Původní chyba
  `10000 Authentication error` existujícího Wrangler OAuth již není blokátorem.
- RUM dataset `rumPageloadEventsAdaptiveGroups` byl introspektován.
  `count` a `sum.visits` vracejí provider odhady, `avg.sampleInterval` sampling;
  filtr používá přesný `requestHost` a `siteTag`.
- Za dokončené UTC dny 2026-10-13 až 2026-10-19 API vrátilo 18 návštěv a
  18 zobrazení, sample interval 1. Stejné období, host a vypnuté vyloučení botů
  v Cloudflare dashboardu potvrdily 18/18. Dashboard časový rozsah byl
  13. 10. 02:00 až 20. 10. 02:00 v GMT+2.
- Za UTC dny 2026-09-20 až 2026-10-19 API vrátilo odhad 80/80,
  sample interval 10. Návštěvy nejsou unikátní lidé; historické výsledky
  nepokrývají EU a nic neslibují o úplnosti jednotlivých dní.

## Veřejný rozsah a podmínky bezpečného sběru

Veřejný katalog, veřejný detail a veřejný formulář jsou zamýšlený rozsah.
Auth/recovery, scanner, administrace, osobní ticket/order/waitlist odkazy
ani Flutter aplikace do sběru nepatří. Nedoplňovat beacon plošně do buildu.
Zachovat `no-referrer`; žádné analytické cookies ani vlastní identifikátory.

Současné pravidlo pro všechny cesty tomuto omezení samo o sobě neodpovídá.
`web_client/src/services/router_service.js` mění historii pomocí `pushState`
a `replaceState`; osobní capability zůstávají ve fragmentech `#order?`
a `#waitlist?`. Musí být doložen i přechod z veřejného obsahu na osobní
obsah v témže dokumentu. Nestačí odebrat script element nebo filtrovat data
v pozdějším přehledu. Nedoplnit druhý beacon vedle automatické injekce.

Preferovat jedinou existující Cloudflare cestu, pokud půjde bezpečně omezit.
Pokud bude nutný manuální loader, nejprve připravit lokální implementaci a
prokázat payloady a životní cyklus; automatická injekce musí být vypnuta před
jeho produkčním zapnutím. Nepoužívat iframe ani vlastní collector jako náhradu.
[Limity pravidel](https://developers.cloudflare.com/web-analytics/limits/)
závisí na tarifu; žádný placený upgrade není autorizovaný.

## Zbývající práce a provozní hranice

1. Doložit konkrétní bezpečné omezení jediného beaconu na veřejný web client.
   Systémový resolver této stanice blokuje beacon (`0.0.0.0`, `::`).
   V následném ověření byl originální script získán přímým HTTPS spojením
   na oficiální IP z veřejného DNS a izolovaný Chrome použil vlastní
   host-resolver-rules. Systémový DNS a uživatelův Chrome nebyly měněny.
   Základní payload homepage byl ověřen; audit všech veřejných/soukromých
   přechodů ještě dokončen není.
2. Po přípravě konkrétní změny ověřit izolovaně katalog -> detail -> formulář
   -> osobní overlay -> auth/soukromou cestu, včetně URL/title/referrer,
   absence nového úložiště a neblokující chyby beaconu.
3. Uživatel následně výslovně autorizoval zapnutí měření Česka/EU. Změna
   `lite` je provedena podle záznamu níže. Tato autorizace sama o sobě
   nepovoluje nový loader, změny aplikace, publikaci, deploy nebo push. Před případnou aktivací
   připravit přesnou CF změnu a případný lokální web release jen pro tento tenant.
4. Po autorizované aktivaci doložit skutečný EU beacon, bezpečné payloady,
   jedinou injekci a nové agregace v Cloudflare dashboardu.

Výsledný stav tohoto sezení: přístup a konfigurace ověřeny, rozsah zúžen
na veřejný web client, nežádoucí admin/backend implementace odstraněna.
Nový loader ani změna veřejného klienta pro sběr zatím nevznikly.
Následně bylo autorizovaně změněno pouze vyloučení EU pro vstupenky.online.
Jiné tenanty, kód aplikace ani pravidla injekce nebyly změněny. Žádné nasazení,
migrace, commit ani push. Omezení sběru na bezpečné veřejné cesty zůstává
samostatně nedokončené.

## Autorizované zapnutí EU 2026-10-20

Uživatel výslovně požádal nastavit měření pro Česko a celou EU.
V existující Cloudflare site pro `vstupenky.online` byla přes její `Manage site`
zvolena možnost `Enable` a potvrzeno `Update`.

Nezávislé zpětné čtení API v `2026-10-20T20:36:13Z` potvrdilo:
`auto_install=true`, `ruleset.enabled=true`, `ruleset.lite=false`.
Cloudflare UI následně rovněž ukazuje `Enable` jako vybranou možnost.
Pravidlo, site, účet a ostatní weby se nezměnily; nebyl přidán druhý beacon.

Tím je doložené uložení konfigurace bez geografického vyloučení EU.
Dřívější historická data se tím nedoplní. První HTTP kontroly z Vídně (VIE)
neobsahovaly beacon ani s browser User-Agentem; samotné zpětné čtení
konfigurace proto není vydáváno za důkaz skutečně přijaté české návštěvy.
Lokální DNS této stanice nadále blokuje `static.cloudflareinsights.com`;
blokace nebyla měněna.

## Skutečné ověření sběru 2026-10-20 20:42 UTC

- V izolovaném headless Chrome, bez uživatelského přihlášení, se na skutečné
  homepage `https://vstupenky.online/` načetl právě jeden beacon a existoval
  `window.__cfBeacon`. Nešlo o ruční vložení scriptu ani replay payloadu.
- Skutečný `POST https://vstupenky.online/cdn-cgi/rum` skončil HTTP 204.
  Odpověď doručil Cloudflare uzel VIE. Nebyl použit vlastní collector.
- Zpětné čtení GraphQL v `2026-10-20T20:42:27Z`, přesný requestHost a siteTag,
  interval od `2026-10-20T20:36:00Z`, potvrdilo dvě agregované návštěvy:
  `countryName=CZ`, count=1, visits=1, sampleInterval=1 v minutě 20:38 UTC,
  a totéž v minutě 20:40 UTC. Sběr z Česka po zapnutí EU je tím doložen.
  Nejde o tvrzení, že jde o dva různé lidi.
- Kontrolovaný skutečný payload homepage: `location=https://vstupenky.online/`,
  referrer ani landingPath nebyly přítomné, žádný cookie header, žádný title.
  Obsahoval pageloadId, výkonové metriky a verzi scriptu `js=2026.10.1`.
  ID stránky není doložený perzistentní identifikátor uživatele.
- Originální JS má SHA-256
  `637381256384554e1cc3309a62fb238a51b83e7f10b2a56d8ba15dbc73ca762e`.
  Jeho funkce `ot` odstraňuje username, password, query a hash před odesláním
  location/referrer. V kontrolovaném zdroji nebylo čtení document.title.
  To samo neřeší capability vloženou přímo do pathname ani všechny další
  výkonnostní atributy. Kompletní audit soukromých přechodů zůstává otevřený.
- Dodatečný syntetický vstup s veřejným testovacím markerem v query/hash
  script v daném načtení neinjektoval, takže nejde o úspěšný runtime důkaz
  odstranění markeru z payloadu. Žádný skutečný osobní token nebyl použit.
- Curl HTML stále někdy neobsahovalo beacon. Samotná taková odpověď proto
  není spolehlivým end-to-end testem nefunkčnosti sběru. Předchozí vysvětlení
  zpožděním konfigurace bylo hypotézou, nikoliv prokázanou příčinou.
- Pages Metrics skutečně ukazují `Web analytics is disabled`, API projektu
  nemá vlastní web analytics tag/token. Přesto funguje RUM cesta zóny.
  Hypotéza, že pro tento provoz nutně chybí zapnutí Pages Analytics, je
  vyvrácena. Druhá Pages integrace nebyla zapnuta a nemá se bez rozmyslu
  přidávat vedle ověřeného beaconu.

Technický závěr: současný RUM sběr z Česka funguje a EU není vyloučená.
Nedokončený samostatný požadavek: omezení výhradně na veřejný web client;
aktuální aktivní pravidlo nadále zahrnuje všechny cesty hostu. Nesmí se tvrdit,
že byl proveden úplný audit soukromí celého webu nebo právní posouzení.

[Cloudflare popis zpracování a absence klientského úložiště](https://developers.cloudflare.com/speed/observatory/rum-beacon/)
uvádí, že provozní IP je přijata při HTTP komunikaci a zahozena před uložením
v core databázích/logách. Absence cookies není obecná právní záruka:
[ÚOOÚ](https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies)
rozlišuje i jiné technologie ukládání a fingerprinting. Tato technická kontrola
nepředstavuje obecné rozhodnutí o právní výjimce pro jakoukoliv konfiguraci.

## Souhrnné zdroje návštěv - potvrzený rozsah

Uživatel z nabízených variant zvolil `Souhrnné zdroje návštěv`.
Existující Cloudflare dimenze `Referer` tento rozsah již pokrývá.
Živé GraphQL čtení nad přesným hostem `vstupenky.online` a existujícím siteTag
vrátilo bez chyby tři skupiny: prázdný referer, `m.facebook.com` a
`www.facebook.com`. Dotaz obsahoval jen `refererHost`, počet zobrazení,
visits a sampleInterval; nikoliv referer path nebo identitu návštěvníka.
30denní interval měl sampleInterval=10, proto jsou počty odhady a nebyly
použity jako přesný počet různých lidí. Prázdný referer znamená přímý nebo
neznámý zdroj; nelze z něj určit, odkud návštěvník skutečně přišel.

Zdrojové domény jsou dostupné v existujícím Cloudflare dashboardu;
není potřeba nová aktivace, další beacon ani úložiště v aplikaci.
[Cloudflare dimenze](https://developers.cloudflare.com/web-analytics/data-metrics/dimensions/)
popisují referer host v dashboardu. [FAQ](https://developers.cloudflare.com/web-analytics/faq/)
potvrzuje absenci podpory UTM a vlastních eventů; kompletní objednávkový
funnel proto není touto funkcí vytvořen a není v odsouhlaseném rozsahu.

Právní závěr nebyl rozšířen na obecnou výjimku ze souhlasu. Souhrnné
neidentifikující výsledky se mají odlišovat od způsobu jejich získávání;
bez cookies samo o sobě neprokazuje právní shodu libovolného trackingu.
Žádné nové propojení se zákazníkem ani objednávkou nebylo přidáno.
Omezení měřených cest pouze na veřejnou část zůstává předchozí otevřenou
technickou položkou, není vyřešené pouhým výběrem přehledu Referer.

## Odkaz z organizační administrace

Uživatel následně požádal o jednoduchý překlik z existující Organization Edit
na přehled v Cloudflare. Lokální změna přidává položku `Návštěvnost webu`
uvnitř stávajícího `OrganizationAdminGuard` jen pro organization ID 3.
Otevírá existující Cloudflare site přehled přes `LaunchUrlService`, na webu
v nové kartě s noopener/noreferrer. Oprávnění k samotným datům ověřuje
Cloudflare přihlášení. Přidány popisky ve všech šesti podporovaných jazycích.

Nejde o nový dashboard v aplikaci ani backendové čtení statistik. Odkaz
obsahuje pouze veřejné account/site identifikátory, žádný API token.
Tato UI změna zatím není nasazena ani publikována.

## Chybějící vstup v profilovém menu a exclude myself

Následný screenshot odpovídá Flutter profilovému menu, kde byl vstup do
Organization Edit pouze malou ikonou pod podmínkou obecného `isAdmin`.
Tento příznak není spolehlivou náhradou ověření organizační role. Lokální
oprava ověřuje `check_is_admin_of_organization` pro aktuální organizaci při
otevření menu a zobrazuje pojmenovanou položku `Nastavení organizace`.
Při chybě kontroly nebo změně identity se položka nezobrazí. Cíl otevírá
existující chráněnou Organization Edit stránku a nemění serverové autorizace.

Webový klient tento vstup neměl vůbec; dostal stejnou pojmenovanou položku,
stejnou kontrolu role a ochranu před opožděnou odpovědí po změně identity či
uzavření menu. Popisky jsou ve všech šesti jazycích. Oprava je pouze lokální.

Ověření: 13 cílených Node testů včetně regresního testu profilového menu,
rolí, chyby RPC a změny identity prošlo; Vite build prošel. Flutter hlavička
byla ověřována cíleným Dart analyzátorem, nikoliv živým backendovým E2E.

Uživatel navrhl `exclude myself`, případně filtr. Dostupné Cloudflare
[filtry a dimenze](https://developers.cloudflare.com/web-analytics/data-metrics/dimensions/)
neobsahují identitu návštěvníka ani IP; přesné zpětné vyloučení vlastní osoby
proto nebylo implementováno ani slíbeno. Filtr soukromých/admin cest je
samostatná možnost přehledu, nikoliv vyloučení vlastních veřejných návštěv.
Lokální browser opt-out před odesláním je možný další směr, ale nevznikl
žádný nový přepínač, cookie, identifikátor nebo změna browser blokování.

## Provedené vyloučení vlastního Chrome

Po výslovném požadavku uživatele `no dobre tak me idealne nejak excludni`
bylo přes Cloudflare dashboard aktivováno jediné Configuration Rule
`Respect browser analytics opt-out` pro zónu `vstupenky.online`.

Expression:

```text
(http.host eq "vstupenky.online" and any(http.request.cookies["festapp_analytics_optout"][*] eq "1"))
```

Akce `set_config`, jediná změněná volba `disable_rum=true`. Pravidlo bylo
po nasazení znovu otevřeno z aktivního seznamu a ověřena uložená expression
i vypnutí RUM. Žádné ostatní pravidlo, obecný EU režim ani jiný tenant
nebyly změněny. Není potřeba deploy aplikace ani placený upgrade.

V uživatelově skutečném Chrome profilu byla v nově otevřené kartě přesného
originu `https://vstupenky.online` nastavena host-only předvolba:
`festapp_analytics_optout=1; Path=/; Max-Age=31536000; SameSite=Lax; Secure`.
Jde o jednotnou booleovskou předvolbu neměření, nikoliv unikátní identifikátor,
a není spojena s účtem/objednávkou ani s IP. Nejsou ukládány nové návštěvy.
Systémový DNS, jiné browser profily a ostatní existující cookies zůstaly beze změny.

Ověření ve skutečném uživatelově Chrome po reloadu nové karty:
optedOut=true, beaconScripts=0, beaconInitialized=false, beaconResources=0.
Nezávislé rozdílové ověření v izolovaném headless Chrome bez lokálního DNS
blokování: bez předvolby beaconScripts=1 a beaconInitialized=true; po
nastavení stejné předvolby a reloadu beaconScripts=0, beaconInitialized=false,
beaconResources=0. Tím je doložen efekt pravidla, nikoliv jen lokální blokátor.
Testovací session byly po ověření uzavřeny.

Rozsah: tento Chrome profil a přesný host vstupenky.online, maximálně rok
nebo do smazání cookie. Na jiném zařízení/profilu je třeba předvolbu nastavit
znovu. Již načtené starší karty mohou mít stále běžící beacon; uživatel je má
jednou obnovit. Historická data se neodstraňují a ostatní návštěvníci se nadále
měří. Zrušení vlastní předvolby: smazat pouze cookie festapp_analytics_optout
pro daný host a obnovit stránku; ponechat ostatní cookies beze změny.

## Kontrola registrace a soukromí 20. října 2026

Registrační text rozlišuje přijetí podmínek a vzetí zásad soukromí na vědomí;
nejde o souhlas s nepovinnou analytikou. JS i Flutter přihlášení ukládají
autentizaci odděleně od opt-out cookie. Kontrola login/logout a cíleného
čištění soukromých dat neodhalila mazání této cookie. Uživatel nebyl kvůli
této kontrole odhlášen; nejde o nově provedený živý login/logout test.

Živá privacy stránka v době kontroly neobsahovala Cloudflare Web Analytics
ani opt-out. Doplněn věcný popis do zdrojů privacy-policy.cs.md a
privacy-choices.cs.md a přegenerovány právní stránky. Renderer --check prošel.
Změny dokumentů jsou lokální, dosud nepublikované.

Tato kontrola není úplné právní schválení: registrace sama nepokrývá
nepovinné sledování, absence cookies sama nedokládá výjimku z ePrivacy.
Zbývá uzavřít právní základ a případný požadavek na souhlas pro skutečný
rozsah RUM v ČR/EU a audit URL cest obsahujících neveřejné identifikátory.
Souhrnné výstupy samy nezaručují anonymitu vstupních dat. Ověřené podklady:
https://developers.cloudflare.com/speed/observatory/rum-beacon/
https://uoou.gov.cz/verejnost/qa-otazky-a-odpovedi/cookies
https://uoou.gov.cz/profesional/metodiky-a-doporuceni-pro-spravce/metodika-k-plneni-informacni-povinnosti-a-k-souvisejicim-ujednanim-vuci-zakaznikum

## Druhá kontrola anonymity a ePrivacy

Oficiální Cloudflare About, RUM beacon a The RUM Diaries potvrzují absenci
trvalého identifikátoru, analytických cookies, localStorage a fingerprintingu
pro sledování jednotlivců napříč návštěvami. Výkonová data ale nejsou jediným
výstupem: služba vykazuje také návštěvy, cesty a zdrojové weby. pageloadId
označuje načtení stránky, nikoliv trvalý účet. IP se podle poskytovatele
zahazuje na edge, nikoliv až po uložení do hlavní databáze.

Proveden lokální test přesné funkce ot z již ověřeného oficiálního beaconu
2026.10.1: query a hash se odstraní, /scan/SYNTHETIC_SECRET zůstává beze
změny. Test nic neposlal na síť. scanner_routes.js skutečně podporuje
/scan/<code>. Všecestné RUM proto nelze bez dalšího prohlásit za anonymní
na všech trasách. Nestačí zákaz injekce na /scan: beacon načtený na veřejné
stránce může sledovat následující SPA navigaci. Ochrana musí pokrýt i tento
přechod a předchozí URL v referreru. Produkční konfigurace nebyla v této
kontrole změněna.

EDPB Guidelines 2/2023 v2, odstavce 52-53: lokální zpracování a zpřístupnění
výsledků přes browser API třetí straně může spadat pod čl. 5(3) ePrivacy.
Absence cookies, identifikace osob nebo trvalého úložiště sama výjimku
nedokládá. Pokyny samy neposuzují všechny výjimky a nejsou specifickým
rozhodnutím o Cloudflare RUM; nelze z nich tvrdit automatický zákaz ani
automatickou výjimku pro tuto službu. Tvrzení, že registrace nebo označení
„výkonová metrika“ samo postačí k měření bez souhlasu, není doloženo.

Podklady:
https://developers.cloudflare.com/web-analytics/about/
https://blog.cloudflare.com/the-rum-diaries-enabling-web-analytics-by-default/
https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf
