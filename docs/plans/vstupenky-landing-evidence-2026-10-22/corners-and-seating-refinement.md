# Revize18:44-18:49 - šipky, čtyři rohy a souvislé editování

Reference používají průhledná kruhová SVG tlačítka přes obrázky, bez dalšího
řádku. Původní paging/keyboard/reduced-motion logika zůstává zachována,
aria-label pojmenovává směr a odkazy jednotlivých akcí zůstávají dostupné.
Umístění vychází z containerquery šířky a skutečného16:9 poměru fotografie.

Mobilní hero střídá TL→BR→TR→BL. Každý motiv má vlastní uložený transform,
takže při mazání zůstává na své původní pozici a partner se nepřemisťuje.
Část geometrie záměrně přesahuje ořez hero, bez horizontálního scrollování
stránky. Desktop kompozice se nemění. Závěr střídá skutečné vektorové motivy
sálu, vstupenky a formuláře po4,8s s jemným prolínáním. Timer běží pouze při
viditelnosti; reduced-motion ukáže statický sál a cleanup odstraní observer.

Cílené testy:6PASS. První batch měl5PASS a cwd-only selhání testu buildstamp
(čeká kořen repozitáře); pouze tato assertion byla znovu spuštěná ze správného
cwd a prošla, bez změny produktu. Logs:/tmp/festapp-corners-tests.log a
/tmp/festapp-corners-test-cwd-fix.log.

Média frozen:build30,033s/refine14s/grid28,599s, desktop1140×792 a mobile820×792.
Nový grid skutečně přidá12židlí,Ctrl-drag vytvoří druhý stůl, společné vložení
zkopírovaného dřevěného stylu upraví oba a podkladový obdélník z=-1 zůstává.
Root vizuálně zkontroloval nativní seating-final.png a porovnal18hashů vůči
receiptu grid-seating-final-proof.json. Owner dekódoval6MP4 a zavřel host.

Browser evidence:corners-review/final-review.json. Všechny4viewports bez
overflow/brokenimages. Mobilní skutečná timelineTL/BR/TR/BL pozorovaná, arrows
forward/back prošly mobil/desktop a všechny3closingmotifs byly pozorované na
obou. Dvě opravy pozorovacího skriptu, bez product fix:rawSVGid není timeline
index a native scrollsnap má2pxpadding (návrat na2 je korektní hranice<=2).
Původní receipts/logy jsou zachované. Zbývající desktop kontroly byly dokončené
odděleně bez opakování již prošlých kroků. Finální preview bylo přegenerované
po aktualizaci media manifestu; ověřovaný JS/CSS/HTML obsah byl stejný.
Lokální revize bez deploy/commit/push.
