# Realizace bezpečných úprav vstupu v objednávce

Ve Festappu si přečti pravidla repozitáře a celý závazný plán
[`order-admission-editing-plan-2026-11-21.md`](order-admission-editing-plan-2026-11-21.md).
Použij ověření `standard` na aktuální autoritativní `main`.

Nejprve zablokuj změnu identity a násobnosti produktů typu `spot` v běžné
editaci na serveru a ověř ostatní doložené vstupy. Uprav společný dialog a
lokalizuj nesrovnalost. Implementuj přidání nové vstupenky a přesun existující
jako oddělené potvrzované akce se sdílenými vlastníky ceny, kapacity a rezervací.
Pro návrh a validaci UI/UX deleguj práci na subagenta Astra Medium
(`gpt-6.2-astra`, `medium`). Využij existující zámky a příkazy podle plánu.
Proveď uvedenou cílenou validaci a u nových případů ověř skutečné zapojení do CI.

Pokud nové důkazy vyvrátí předpoklad plánu, uprav plán a zaznamenej důvod.
Odstraň možnost upravovat vstup přes obecný picker a všechny nalezené
obchozí zápisy v dotčených cestách. Dodej úplné akce bez souběžných variant,
trvalých servisních výjimek nebo nedokončených částí.

Nasazení a jednorázová oprava produkční objednávky `7466` vyžadují samostatnou
autorizaci. U opravy navíc potvrď zamýšlenou variantu a ověř výchozí stav,
kapacitu, platební fakta a dopad na doručení. Při předání uveď výsledky testů
a přesný stav produkční ochrany a incidentu.
