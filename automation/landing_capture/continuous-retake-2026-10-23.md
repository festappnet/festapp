# Souvislé přetočení obou videí

Tato verze nahrazuje předchozí sestřih z téhož dne. Zadání: pohyb hned od
začátku a nové souvislé záběry místo dalších oprav střihu.

- Sál začíná hotovou řadou pěti stolů a skutečným přetažením dalšího stolu
  z palety. Následuje jeho zarovnání pod první stůl a dva samostatné přírůstky
  židlí. Výsledkem je 6 stolů a 38 židlí. Kopírování s přechodným varováním
  o překryvu se v tomto průchodu nepoužívá, takže není důvod vystřihovat snímky.
- Formulář zachovává vybranou Vstupenku po celý záběr. Přidá Večeři a tři
  placené možnosti: Kuřecí 180 Kč, Vegetariánská 160 Kč, Veganská 160 Kč.
  Potom přidá samostatné pole Poznámka. Nevybírá je k další editaci, která
  v předchozí verzi sbalila rozpracovanou Vstupenku a skokově posunula obsah.
  Kurzor se mezi ovládacími prvky přesouvá souvislou nativní cestou.

Každý výstup používá jediný interval skutečných zdrojových snímků při rychlosti
1x. Neobsahuje vnitřní střih, zrychlení, vynechané kolizní snímky ani vkládané
statické záběry. Ořezáno je pouze úvodní technické čekání před prvním pohybem.
Počátek pohybu je určen rozdílem skutečných zdrojových snímků a ověřen i
v exportu. Koncový výsledek má krátké přirozené podržení.

Reprodukce používá `layout/row_ready.py`, `admin/continuous_form.py` a
`encode_revision.py CHAPTER TAKE OUTPUT --start-at TIMESTAMP`. Před nahráváním
připravit reálný editor s řadou pěti stolů nebo čistý lokální formulář se
základním vstupným. Backend, prohlížeče a přihlašovací údaje zůstávají izolované
stejně jako v předchozí dokumentované přípravě. Zdrojové nahrávky, časy,
kontrolní snímky a exporty jsou v
`~/Downloads/festapp-video-continuous-20261023/`; nejsou součástí Git.

Rozměry zachovávají současné místo na stránce: sál 1140x792 / 820x792,
formulář 1200x804 / 720x638. Mobilní varianta je výřez desktopového editoru.
Publikační manifest musí uvádět nové skutečné délky a nové hashe odkazů na
videa i postery, aby se nevracela předchozí verze z HTTP cache.
