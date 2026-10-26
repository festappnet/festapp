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
