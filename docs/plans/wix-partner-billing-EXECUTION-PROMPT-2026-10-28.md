# Dokonči Wix Partner Billed integraci

Pracuj v /Users/miakh/source/festapp. Přečti v plném znění autoritativní plán:

`docs/plans/wix-partner-billing-plan-2026-10-28.md`

Dodrž AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a verification: standard;
produkční vydání musí projít všemi povinnými release gates. Navazuj na hotový,
lokálně otestovaný původ objednávek a CSV/API projekci, nepřepisuj je od začátku.

Cíl: provozuschopný native Wix doplněk s individuální smluvní sazbou pořadatele,
reportováním pouze skutečných našich servisních příjmů a bezpečným charge/refund
doručením. Dokonči zdroj účetních dat a akvizice, dispatcher s unknown-outcome
reconciliation, OSVČ dodatek/activation a koordinovaný rollout prod/festapptickets.
Nakonec proveď marketplace submission a dolož skutečný review/publication stav.

Začni kontrolou poslední odpovědi ve stávajícím threadu Wix a identifikací
skutečného fee settlement zdroje. Sazba nemá default. Původ objednávky není
akviziční důkaz. Nevymýšlej ledger, účtované částky, podpis ani úspěšnou aktivaci.
Zachovej opravu replay: nový podpis nesmí změnit pending purchase intent.

Postupuj po vlnách. Při vyvrácení faktu aktualizuj plán důkazem. Bez paralelního
checkoutu, druhých výpočtů, spekulativních fallbacků a oslabení release gates.
Respektuj cizí rozpracované změny. Rutinní deploy deleguj podle AGENTS.md;
nezahajuj nezávislé agentní audity. DB a backend nasadit před klientem a widgetem,
chránit email worker a nikdy nerecreatovat Functions částečným compose.

Dřívější souhlas s nulovými jednorázovými poplatky a vydáním platí; nevyžaduj ho
znovu. Nový placený/právně odlišný závazek ani produkční testovací nákup, hold či
fiktivní billing událost není tímto promptem autorizován. U externího blockeru
pokračuj nezávislou prací a přesně jej popiš. Hotovo znamená splnění celého plánu,
nikoli jen přípravu CSV, lokální testy nebo odeslanou marketplace žádost.
