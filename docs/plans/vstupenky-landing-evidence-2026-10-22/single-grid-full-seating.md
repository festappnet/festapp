# Jeden gridový stůl s plným obsazením

Aktuální zadání nahrazuje předchozí dva gridové stoly: jediný malovaný stůl,
židle do skutečného nativního maxima a několik jiných stolů okolo.
Ostatní klipy, desktop rozměry a animace zůstávají zachované.

Maximum určuje skutečný počet polygonSurfaceSlots/tableCapacity. Capture
používá podporované přidávání židlí až po deaktivaci +, ne pevné číslo nebo
odhad. Kulaté a obdélníkové stoly používají nativní nástroje a ponechávají
průchody. Druhá gridová kopie a její kopírovací záběr se odstraňují.

Finální nativní readback: přesně1grid,2circle,2rect. Grid58/58kapacity,
celkem82židlí, collisionPairs=[]; plus je deaktivované na skutečném maximu.
Root vizuálně ověřil mixed-capacity.png, mixed-named.png a finální skutečně
dekódovaný mobileframe mixed-verified-encoded/layout-grid-mobile.jpg. Všechny
stoly jsou ve výřezu, s průchody a bez druhé gridové kopie.

Finální klip23,933s,1140×792/mobile820×792; oběMP4decodePASS(owner).
Root ověřil6hashů proti mixed-grid-final-proof.json a sestavil lokální preview.
Ostatní source/média beze změny, proto bez opakování jejich prošlých testů.
Chybný pozdější pokus vložit podklad byl z exportu celý vyřazen; aktuální
finále používá původní průhledné plátno. Žádné přelepování pixelů.
Owned browser i55907host ukončené.
Lokální revize bez deploy, commit nebo push.

## Navazující úprava a uzavření smyčky

Nové skutečné výběžky mění nativní kapacitu na64/64. Celkem88židlí, stále
1grid+2circle+2rect a collisionPairs=[]. Všech pět stolů i jejich navázané
židle mají wood material. Původní58 i dodatečné6přidávání jsou zpomalené2×.
Root zkontroloval all-wood-encoded/layout-grid-mobile.jpg a nativní readback
all-wood-grid-final-proof.json.

Na konec celého editorplaylistu připojen původní skutečný odstřižený úvod
s kreslením pódia a stěn. Přechod z hotové scény je dokumentovaný střih do
archivního prázdného sálu, ne simulované mazání. Končí0,4s podržením skutečného
prvního frame následujícího layout-build, aby navázala stejná paleta/pódium/stěny.
Finální layout-grid45,866s,1140×792/mobile820×792, bothdecodePASS. Root ověřil
finální hashy z editor-loop-final-proof.json a prohlédl skutečný dekódovaný
loop-lastframe. Preview bylo obnoveno po freeze. Procesy vypnuté, bez deploy.
