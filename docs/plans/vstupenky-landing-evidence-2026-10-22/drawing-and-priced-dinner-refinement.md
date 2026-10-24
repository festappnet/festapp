# Revize19:40-19:43 - přesahy, souvislé SVG a placená večeře

Příčina nesouvislého kreslení: kombinace pathLength=1 a non-scaling-stroke
při SVG scale mění fyzickou délku dash patternu, zatímco pero používá původní
geometrii. Deterministický minimální browser repro:
/tmp/festapp-dash-diagnostic.html, screenshot drawing-fix-review/dash-diagnostic.png.
Stejný obdélník při scale2 a50% normalizovaného dashoffset: non-scaling varianta
má přerušené segmenty a konec mimo červený marker; scaling varianta souvisle
končí přesně u markeru. Nejde jen o načasování nebo překryv motivů.

Fix obou animací: v animovaných cestách vector-effect:none, dash i pero jsou
ve stejné SVG geometrii. Šířka čáry je zvlášť kompenzovaná screenCTMscale
na1,45pxdesktop/1,65pxmobile a1,2pxv závěru. Dosud nekreslené cesty jsou
skryté. Bez zavedení nové animační závislosti.

Hero background používá plnou šířku viewportu, větší motivy ažscale1,9 a
záměrné přesahy na stranách/shora, se sníženou opacity. Mobilní kompozice
nadále střídá4rohy; motivy jsou větší a částečně mimo ořez hero. Hlavní
text a CTA nejsou přesouvané.

Node6PASS. BrowserPASS390/1440: skutečné přesahy, bez horizontálního
overflow;3closingmotifs v draw i hold. AssertvectorEffectnone zachycuje původní
příčinu a screenCTM×strokeWidth=1,2px ověřuje zachování tloušťky. Vizuální
screenshot potvrzuje souvislý obrys končící u pera. Nový WebMdecodePASS.

Layout-build19,833s začíná těsně před prvním úplným dragem, úvodní kreslení
pódia z tohoto klipu odstraněné podle změny zadání. Form-build17,3s skutečně
přidává večeři do Vstupenky přes nativní produktovou skupinu a nastavuje ceny
Kuřecí180Kč/Vegetariánská160Kč. Dřívější generické bezplatné pole odstraněné;
uložení/readback a reloadPASS. Mobilní720×638 i desktop1200×804 zachovávají
čistý výřez bez spodní lišty.4MP4decodePASS(owner), aktuální hashy ověřené
rootem proti paid-dinner-direct-layout-proof.json. Preview znovu sestavené po
mediafreeze, JS/CSS shodné s browserreceipt.

Evidence:drawing-fix-review/final-review.json, předchozí nepřesné implementace
se nepovažují za tuto finální opravu.
Bez deploy/commit/push.
