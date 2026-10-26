# Lokální ověření časové agregace

SQL test temporal_feed_test.sql ověřuje 35 smíšených akcí v jednom dni,
týdenní skupinu, nedotčené formulářové události, stejnojmenné akce, úplné
stránkování souhrnu i 35 dětí, neměnný ack, pozdní doručení, neplatné
kalendáře/cursory a revokaci práv. Celá notifikační SQL sada: 13 PASS.
Souběh: 6 PASS. Cílené klientské testy: 19 PASS, včetně 23/25hodinových dnů.

Skutečný lokální full-app průchod používal task-owned Supabase 57421/57422
a syntetickou historii periods.sql, bez produkčních volání a s pozastaveným
e-mailovým workerem. Vidět 35/5 na zavřených skupinách, rozbalení 30+5 položek,
samostatné zavření formuláře a 1 místo pouze pro více-místový formulář.
Navigace/čtení používá skutečné RPC; externí push SDK callback je izolovaný
stejně jako v dosavadním notification_center_e2e.dart.

Browser scroll přes DOM neřídí spolehlivě Flutter canvas; kontrola poslední
stránky použila skutečný keyboard End a tlačítko Show more. Screenshoty
a accessibility výpisy zachycují syntetické zákazníky.

Kompletní canonical client runner: 2345 případů, 2 přeskočené, 0 selhání;
architecture a semantic inventory PASS. Viz client-summary.json.

Připojen novější main c77397611: vstup do skeneru a nápověda k publikovanému
vložení na web. Dart/test/package inputs zůstaly shodné s plným klientským
během. Kompletní webová sada nad finální kombinací: 784 případů, 754 PASS,
30 přeskočených, 0 selhání (web-summary.json).

Finální mobilní průchod z čistého checkoutu: [zavřené skupiny](collapsed-mobile.png),
[rozbalený týden](weekly-expanded-mobile.png). Accessibility výpis potvrzuje všech
pět týdenních řádků. Čerstvý head prohlížeče měl viewport nastaven před spuštěním
Flutteru; izolované browser sessions a vlastněný Flutter server byly ukončeny.

Pozdější main ca63c704a odstraňuje akci novinek z hlaviček Flutteru.
Je rovněž připojen; finální kombinace prošla dalšími 52 dotčenými navigačními
testy. SQL cursor navíc nezávisí na session TimeZone (ověřeno střídáním UTC
a Europe/Prague mezi stránkami) a parser má správnou STABLE volatilitu.
