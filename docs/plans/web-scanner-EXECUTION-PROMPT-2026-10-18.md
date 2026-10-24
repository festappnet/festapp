# Implementuj webový skener podle revize 3

Pracuj v `/Users/miakh/source/festapp`. Implementuj celý rozsah plánu a dokonči všechny lokálně proveditelné části i jejich ověření. Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a oba autoritativní dokumenty celé:

- `docs/plans/web-scanner-plan-2026-10-18.md`
- `docs/plans/web-scanner-contract-2026-10-18.md`

Cíl: kompletní skenování jako výchozí vanilla JS/HTML web klient, nastavitelné produkty/pole, pravdivé počty, kamera/ruční/HID vstup a připravený offline provoz s trvalou frontou a vysvětlitelnými konflikty. Zahrň programovou kontrolu a samostatný recepční QR login podle jejich současných oprávnění. Nativní hranice zachovej podle deletion ledgeru. Produktové čerpání, odchody a další analytiku nepřidávej.

## Postup a efektivita

1. Udělej jediný cílený rozdílový průzkum vůči doloženému stavu plánu. Zachovej cizí rozpracované změny. Pokud se zásadní fakt změnil, oprav příslušnou část obou dokumentů; neopakuj celý architektonický průzkum.
2. Postupuj ve vlnách plánu. První integrovaný řez je session -> ruční lookup -> skutečný IDB outbox -> potvrzovací RPC -> receipt -> restart/retry stejné operace. Propoj jej již ve vlně 2. Nevytvářej dočasný online writer bez trvalé fronty.
3. Kameru/HID, nastavení a ostatní skenovací režimy připoj ke stejnému controlleru a rendereru. Poté doplň snapshots, offline recovery, všechny vstupní routy a úklid nahrazených webových cest.
4. Reuse existující komponentový lifecycle, Supabase klient, ThemeService, lokalizaci, SQL guards a jediný PWA worker. Drž oddělené UI, input, transport, store a sync odpovědnosti; nebuduj obecný workflow/auth/offline framework. Jeden profil akce a řazení polí tlačítky stačí.
5. Dodrž provozní rozpočet plánu: jeden RPC lookup a jeden RPC confirm v běžném toku; žádný kompletní export/settings refresh/COUNT na každý scan. Summary obnovuj omezeně a snapshots sloučeně, decoder načítej jen pro scanner. Změř bundle/payload, RPC počet a dobu lookupu/synchronizace na určené fixture.

## Závazný serverový a offline kontrakt

Nové serverové rozhraní jsou výhradně **Supabase RPC SQL funkce v `public`, volané přes `supabase.rpc(...)`**. Žádný nový REST server ani nové Edge Functions pro scanner. Recepční login zachovává existující `exchange-login-qr` a nesmí přepnout účet pracovníka otevřeného scanneru.

Online i offline potvrzení používají stejný trvalý outbox a jediný `sync_scanner_operations` RPC. Nefunkční IDB blokuje potvrzení i online, čtení zůstává možné. Žádný paměťový fallback vydávaný za uložené potvrzení. Server vlastní oprávnění, eligibility, zamykání, ticket write a idempotentní receipt. Zaveď jediný registry scanner receipts dle kontraktu, nikoli druhou kopii téže operace.

Sjednoť také původní ticket-first wrappers na kanonické parent-before-ticket zamykání. Retry po ztracené odpovědi nesmí znovu použít ticket. Historický receipt po admin unused zůstává historický; neobnovuje used ani starý overlay. Snapshot musí být konzistentní, minimalizovaný, kompletní a atomicky aktivovaný. Rotace/expirace session nesmí frontu smazat ani ji automaticky přepsat pod jinou identitu. Zachovej serverové scope checks, abuse limity a nativní kontrakty; nepoužívej persistentní aplikační triggery.

## Závazná úroveň UI podle Astra Medium

Priorita je scan -> výsledek -> akce. Mobil má kompaktní hlavičku a stavový řádek; podrobné metriky pod „Přehled“. Navigace je „Skenovat / Historie / Offline“, hledání patří do „Ručně“. Kamera po načtení uvolní místo detailu. V každém stavu je jediná dominantní akce; po dokončení „Další vstupenka“.

Použij Festapp tokeny, Futura, oba motivy, dotykové cíle alespoň 48 CSS px a text/ikonu vedle stavové barvy. Na 390 × 844 px jsou u běžných údajů stav, jméno, první produkt a CTA viditelné bez scrollování. Na 320 px, dlouhých textech a při 200% zoom nezmizí obsah ani fokus. Platební překážka a původ ověření se nesmějí skrýt. HID Enter jen načte kód. Lokální pending nikdy nepředstírá serverový úspěch.

Původní smyšlený HTML prototyp byl odstraněn při [úklidu](repository-size-cleanup-RESULT-2026-10-21.md). Nepřebírej jeho demo ovladače, paměťový stav ani CSS do produktu. UX rozhodnutí Astry jsou zapracovaná v plánu; novou širokou návrhovou fázi neopakuj.

## Ověření a dokončení

Verification: standard. Po ucelené změně proveď nejlevnější odpovídající repo validation batch. Scénáře C01-C18 seskup podle skutečných seams; neopakuj passing checks bez změny pokrytých vstupů. SQL souběh ověř dvěma DB spojeními nad explicitně izolovanou lokální DB. Dolož nenulový počet skutečně provedených testů. Full Flutter/release build spouštěj až při příslušném release zadání nebo povinné repo gate.

Proveď jeden cílený izolovaný browser průchod mobilním i desktopovým výsledkem, offline konfliktem a storage failure, se screenshoty klíčových stavů. Bez vizuální kontroly neoznačuj UI za hotové. Hardware kameru/čtečku ověř na cílových zařízeních před tvrzením release-ready; nedostupnou fyzickou kontrolu přesně uveď a dokonči ostatní dostupnou práci.

Hotovo vyžaduje kompletní webové cesty, odstranění nahrazených webových entrypoints, zachování explicitních nativních hranic a ověřenou obnovu fronty. Nezůstávej u online-only části, placeholderů nebo trvalého V1/V2 přepínače. Nevkládej další obecné refaktory do kritické cesty.

Produkční migrace, deploy, commit/push a další tenant rollout vyžadují vlastní zadání. Při následně autorizovaném nasazení dodrž jediný vybraný tenant, lokální build a `automation/deploy_direct.sh`; rutinní provedení deleguj podle AGENTS.md. Na závěr stručně uveď výsledek, ověřené scénáře, měření výkonu, odstraněné cesty a přesné zbývající provozní/hardware kroky.
