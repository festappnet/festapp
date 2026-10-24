# Revize19:21-19:23 - menší desktop ukázky a kreslení v závěru

Desktop nad760px: formulář max760px, scanner560px, přehled640px; další limit
odvozuje šířku z výšky viewportu a skutečného poměru klipu. Mobilní pravidla
jsou zachována. Žádné ořezávání nebo deformace videa.

Závěr používá skutečné path délky a normalizované stroke-dashoffset. Aktivní
je vždy jediný motiv. Sál→vstupenka→formulář se postupně kreslí2s, čistě
vyplní0,3s, podrží a následně smaže0,45s před dalším motivem. Pohyb pera
sleduje skutečný konec právě kreslené cesty. RAF běží jen při viditelnosti;
reduced-motion ukazuje statický plný sál, cleanup ruší vlastní RAF/observer.

Podpis Festapp zůstává uprostřed a linkuje festapp.net; odstraněno „od“
z viditelného textu i aria-label.

Cílený Node batch6PASS (2generator +4player/carousel), správné cwd obou sad.
BrowserPASS:390×844 a1440×800/1000, všechny3video caps. Závěr pozorovaný
ve skutečných draw i hold fázích pro všechny3motivy, přesně1viditelný motiv,
částečně nakreslená cesta a pohybující se pero. Nedotčené cesty jsou skryté,
aby se jejich konce neobjevovaly před kreslením. Footer bez „od“. Recording
closing-drawing.webm decodePASS. První recordstart resetoval scroll, takže
pozorování čekalo mimo footer; runtimeerrorprobe byl čistý. Zopakovaná byla
pouze nedokončená část s posunem až po recordstart, potom affected drawcheck
po skrytí dosud nekreslených cest. Původní receipts jsou zachované.

Orders19,1s zachovává13,1sreport→orders a doplňuje6s skutečného editoru
interní poznámky objednávky250/akce8: null→Příchod v18:30. Úspěšný save a
persistence po skutečném reloadu, paymentstatepaid beze změny. OběMP4 decode
PASS,4hashy z order-edit-final-proof.json ověřené rootem. Žádné outbound
zprávy ani změny plateb. Browser/Flutter/disposablebackend ukončené, fixture
backup zachovaný. Lokální preview bylo obnoveno po finalmediafreeze.

Evidence:compact-review/final-review.json a order-edit-final-proof.json.
Bez deploy, commit nebo push.
