# Fakturoid - příprava veřejného konektoru

Produkt: **vstupenky.online**. Stav k 2026-11-13: podklady připravené,
dotaz na podmínky odeslán podpoře, veřejné zařazení neproběhlo.
Nejde o instalační plugin; stávající napojení
je součástí backendu Festapp. Přijetí do katalogu rozhoduje Fakturoid.

## Cíl a další krok

Zveřejnit propojení v [oficiálním katalogu Fakturoidu](https://www.fakturoid.cz/katalog-aplikaci).
Fakturoid přijímá otestované integrace a ověřuje kladné reference. Postup se
domlouvá přes podpora@fakturoid.cz. Registrace OAuth aplikace je samostatná
operace a sama nevytvoří záznam v katalogu.

Před veřejnou nabídkou je potřeba dokončit připojování jednotlivých pořadatelů
přes Authorization Code Flow. Aktuální Client Credentials implementace není
důkazem připravenosti veřejného konektoru. Fakturoid tento způsob pro aplikace
s více zákazníky nedoporučuje a upozorňuje na možné odebrání přístupu integrace.
Nejde o doloženou samostatnou formální podmínku katalogového zápisu.

- [Rozsah implementace, důkazy a zbývající práce](READINESS.md)
- [Návrh textu do katalogu](submission/description.cs.txt)
- [Dotaz na podmínky odeslaný 2026-11-13](submission/inquiry.cs.txt)
- [Pracovní návod pro pořadatele](../../docs/guides/fakturoid.cs.md)

## Zdroje podmínek

Znovu ověřeno 2026-11-13:

- [Zařazení, reference a kontakt](https://www.fakturoid.cz/podpora/automatizace/propojeni-s-webem)
- [Založení integrace a testovací účet](https://www.fakturoid.cz/podpora/automatizace/api)
- [API v3: autentizace jednotlivce a aplikace pro více zákazníků](https://www.fakturoid.cz/api/v3/authorization)

Veřejně doloženou cenu za zařazení nemáme. Platí [požadavek nulových fixních
nákladů vydavatele](../README.md#publisher-cost-constraint). Běžný tarif
pořadatele a jeho API limity jsou jiná věc. Případné poplatky za zápis či jeho
udržování je třeba potvrdit před přijetím podmínek.

Veřejné [obchodní podmínky](https://www.fakturoid.cz/obchodni-podminky)
neposkytly konkrétní sazbu za zařazení ani udržování katalogového záznamu.
Tvrzení o bezplatném API propojení pro zákazníky není potvrzením ceny za
zveřejnění konektoru. Dne 2026-11-13 byl po pokynu vlastníka odeslán dotaz
na podpora@fakturoid.cz: požadované podklady, reference od jednoho zákazníka,
testovací účet a fixní poplatky. Gmail vrátil message/thread ID
`1a1d1fe461fd411d` a štítek `SENT`. Odpověď a přijetí do katalogu zatím
nejsou doložené. Zákazník nebyl jmenován.
