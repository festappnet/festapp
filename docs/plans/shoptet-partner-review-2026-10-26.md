# Shoptet: dvě kola kritiky

26. 10. 2026. Kontrolována připravenost podkladů k technickému jednání, nikoli funkčnost dosud neexistujícího doplňku.

## První kolo

Nezávislý kritik `/root/shoptet_critic_round1` požadoval šest úprav:

| Nález | Zapracování |
| --- | --- |
| P1: chyběl finanční kontrakt externího checkoutu | Technická příloha §5: privilegovaný snapshot ceny a finanční fakta, stávající projekce, ochrany bank/Stripe i e-mailů. |
| P1: instalace v obchodním klíči umožňovala duplicitu po reinstalaci | Plán pravidlo2 a příloha §3: stabilní obchodní identita oddělená od generace oprávnění. |
| P1: po uninstall není zaručené API | Příloha §6 rozlišuje vlastní výpadek, suspend a odinstalaci, obsahuje doložený ruční postup. |
| P1: neurčený přechod krátkého holdu na objednávku | Příloha §4 obsahuje stavy, původce přechodu a oddělené termíny. |
| P2: jedna objednávka vs více akcí a změny mapování | Příloha §1 a §3: první rozsah, serverové vynucení nebo nové rozhodnutí, zmrazené mapování prodeje. |
| P2: neurčité fronty, obnova a metriky | Příloha §6 a §7: trvalé přijetí, retry, opravné případy, reconciliation, upozornění a důkazní matice. |

Obchodní návrh byl zkrácen podle skillu `miakh-voice` a jeho `references/voice-profile.md`; neznámé provizní podmínky nepřijímá předem.

## Druhé kolo

Jiný nezávislý kritik `/root/shoptet_critic_round2` zkontroloval upravený plán, přílohu, návrh a realizační zadání. Výsledek: **PASS pro technické jednání, bez dalších P1/P2 nálezů**. Potvrdil rozlišení ověřených faktů a otevřených platformních možností a přirozený styl obchodního návrhu.

Po tomto kole byly zapracované dvě drobné připomínky: odstranění opakovaného slovesa v obchodním návrhu a upřesnění, že HTTP načtení drží aplikační lease, nikoli SQL transakci přes síť. Jiné věcné změny po druhé kritice neproběhly.

## Závěrečná kontrola dokumentů

Relativní odkazy existují a dokumenty nemají šablonové placeholdery. Testy aplikace nebyly spouštěny, protože se měnily pouze plánovací dokumenty. Žádné podání, implementace, placený závazek ani produkční operace neproběhly. Přístupy, kapacitní kontrakt a partnerské podmínky nadále čekají na Shoptet.

Otisky finálních dokumentů po drobné redakci:

| Dokument | SHA-256 |
| --- | --- |
| `shoptet-partner-onboarding-2026-10-26.md` | `a4e6ded856fa5d428b92383a5a47ee8b984aa121152af73941ec96dc18ae11c1` |
| `shoptet-partner-technical-2026-10-26.md` | `8b432a7987d79c018b7d49fb2d7152c592b543cf2da03023eb45c3b2fc026743` |
| `shoptet-partner-proposal-2026-10-26.md` | `0a661d1e1a0e24eb709669507557ac3d6966b0ad2d86e9eaa7c416336dc4157d` |
| `shoptet-partner-EXECUTION-PROMPT-2026-10-26.md` | `8d505847c273149036fd500835e48a32d7bdca0e80bea20a55fe6f14de03b2f6` |

Následná uživatelská oprava URL: odkaz v návrhu nyní míří přímo na homepage služby. Jde o opravu odkazu po původních dvou kritikách, bez změny návrhu spolupráce.
