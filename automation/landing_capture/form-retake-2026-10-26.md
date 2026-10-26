# Přetočení formuláře - 2026-10-26

Původní scénář vyplňoval každé pole dvakrát. Opravný zápis byl vidět jako
smazání již zadané ceny a opětovné zadání stejné hodnoty.

Nový průchod zachovává jeden souvislý záběr při rychlosti 1x:

1. Přidat nový typ produktu Večeře.
2. Přidat Kuřecí večeři a zadat 180 Kč.
3. Přidat Vegetariánskou večeři a zadat 160 Kč.
4. Přidat Veganskou večeři a zadat 160 Kč.
5. Ukázat hotové možnosti a přidat samostatné pole Poznámka.

Každé pole se nejprve zaměří přes skutečný přístupnostní prvek Flutteru.
Po ustálení editačního vstupu se vyplní právě jednou. Hodnota se ověří před
opuštěním pole; neúspěšný průchod se zahodí místo opravy během nahrávání.
Po nahrání se formulář uloží a ceny se ověří v izolované databázi.

Záznam používá skutečnou aplikaci s českou lokalizací, viewport 1000x1000,
syntetickou organizaci 1, příležitost 1 a formulář 1. Lokální backend běží
výhradně na 127.0.0.1:56831 v projektu festapp-form-retake-20261026.
Oznámení jsou izolovaná stejně jako v E2E vstupním bodu. Produkční data
se při natáčení nepoužívají. Mobilní export je prezentace desktopového editoru.

Zdrojové snímky, cue manifesty a výstupy zůstávají v externím adresáři
~/Downloads/festapp-form-retake-20261026/. Desktopový a mobilní export,
postery a aktualizované hashe odkazů se publikují společně.
